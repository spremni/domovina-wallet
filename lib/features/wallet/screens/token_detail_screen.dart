import 'dart:async';
import 'dart:math' as math;

import 'package:domovina_wallet/core/constants/solana_constants.dart';
import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/transaction_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Simple args wrapper passed via GoRouter.extra
class TokenDetailArgs {
  final TokenBalance token;
  const TokenDetailArgs({required this.token});
}

class TokenDetailScreen extends StatefulWidget {
  final TokenDetailArgs? args;
  const TokenDetailScreen({super.key, this.args});

  @override
  State<TokenDetailScreen> createState() => _TokenDetailScreenState();
}

class _TokenDetailScreenState extends State<TokenDetailScreen> {
  late final SolanaRpcService _rpc;
  WalletModel? _wallet;
  late TokenBalance _token;
  bool _loading = true;
  bool _loadingMore = false;
  List<TransactionModel> _txs = const [];
  String? _before; // pagination cursor (signature)

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    final incoming = widget.args?.token;
    _token = incoming ?? TokenBalance(mint: null, symbol: 'SOL', name: 'Solana', balance: BigInt.zero, decimals: 9, iconUrl: null, isNative: true);
    scheduleMicrotask(_loadInitial);
  }

  @override
  void dispose() {
    _rpc.close();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final wallets = await SecureStorageService.instance.getWalletList();
      if (wallets.isEmpty) {
        if (!mounted) return;
        context.go('/onboarding');
        return;
      }
      final w = wallets.firstWhere((e) => e.isDefault, orElse: () => wallets.first);
      _wallet = w;

      // Refresh token balance from chain to ensure latest
      await _refreshTokenBalance(w.publicKey);

      // Load first page of tx history and filter
      await _loadMore(reset: true);
    } catch (e) {
      debugPrint('TokenDetail: initial load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshTokenBalance(String owner) async {
    try {
      if (_token.isNative) {
        final lamports = await _rpc.getBalance(owner);
        _token = TokenBalance.nativeSolFromLamports(lamports);
      } else {
        final tokens = await _rpc.getTokenAccounts(owner);
        final found = tokens.firstWhere(
          (t) => t.mint?.toLowerCase() == _token.mint?.toLowerCase(),
          orElse: () => _token,
        );
        _token = found;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('TokenDetail: refresh balance failed: $e');
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_wallet == null) return;
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final limit = 20;
      final sigs = await _rpc.getSignaturesForAddress(_wallet!.publicKey, limit: limit, before: reset ? null : _before);
      if (sigs.isEmpty) {
        setState(() => _before = null);
        return;
      }
      // Fetch transaction details in parallel
      final txsJson = await Future.wait(
        sigs.map((s) => _rpc.getTransaction(s, ownerAddress: _wallet!.publicKey)),
        eagerError: false,
      );
      final all = txsJson.whereType<TransactionModel>().toList();
      // Filter for this token
      final filtered = all.where((tx) {
        if (_token.isNative) return tx.token.isNative;
        final m = _token.mint?.toLowerCase();
        final txMint = tx.token.mint?.toLowerCase();
        return m != null && m.isNotEmpty && m == txMint;
      }).toList();
      filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        if (reset) {
          _txs = filtered;
        } else {
          _txs = [..._txs, ...filtered];
        }
        _before = sigs.isNotEmpty ? sigs.last : null;
      });
    } catch (e) {
      debugPrint('TokenDetail: loadMore failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neuspješno učitavanje povijesti.')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  IconData _iconForToken(TokenBalance t) {
    final info = t.mint != null ? (TokenRegistry.byMint(t.mint!) ?? TokenRegistry.nativeSol) : TokenRegistry.nativeSol;
    switch (info.iconKey) {
      case 'solana':
        return Icons.hexagon;
      case 'euro':
        return Icons.euro;
      case 'dollar':
        return Icons.attach_money;
      case 'hr_checkerboard':
        return Icons.shield;
      default:
        return Icons.token;
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label kopiran')));
  }

  void _showReceiveSheet() {
    final addr = _wallet?.publicKey ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.south_west, color: cs.primary),
              const SizedBox(width: 8),
              Text('Primi ${_token.symbol.isEmpty ? 'TOKEN' : _token.symbol}', style: text.titleMedium?.copyWith(color: cs.onSurface)),
              const Spacer(),
              IconButton(icon: Icon(Icons.close, color: cs.onSurfaceVariant), onPressed: () => context.pop()),
            ]),
            const SizedBox(height: 12),
            Text('Adresa za primanje', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
              child: Row(children: [
                Expanded(child: SelectableText(addr, style: text.bodyMedium?.copyWith(color: cs.onSurface))),
                IconButton(onPressed: () => _copy(addr, 'Adresa'), icon: Icon(Icons.copy, color: cs.primary)),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Ovo je Vaša javna adresa. Za SPL tokene pošiljatelj može poslati na ovu adresu; Vaš pridruženi token račun bit će automatski korišten.', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final title = (_token.symbol.isEmpty ? (_token.mint?.substring(0, 6) ?? 'Token') : _token.symbol) + (_token.symbol.isNotEmpty ? ' • ${_token.name}' : '');
    final decimals = _token.decimals;
    final balanceUi = _token.uiAmount;
    final balanceStr = balanceUi.toStringAsFixed(math.min(6, decimals));
    final fiatStr = '≈ € —';

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(_iconForToken(_token), color: cs.primary)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator.adaptive(
              onRefresh: () async {
                if (_wallet != null) await _refreshTokenBalance(_wallet!.publicKey);
                await _loadMore(reset: true);
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // Balance Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(balanceStr, style: text.displaySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)), child: Text(_token.symbol.isEmpty ? 'TOKEN' : _token.symbol, style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 6),
                      Text(fiatStr, style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Icon(Icons.trending_up, color: cs.onSurfaceVariant, size: 18),
                        const SizedBox(width: 6),
                        Text('24h: —%', style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // Action Buttons
                  Row(children: [
                    Expanded(
                      child: AppButton(
                        label: 'Pošalji',
                        icon: Icons.arrow_upward,
                        onPressed: () => context.push('/send'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: 'Primi',
                        icon: Icons.arrow_downward,
                        secondary: true,
                        onPressed: _showReceiveSheet,
                      ),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // History
                  Row(children: [
                    Expanded(child: Text('Povijest transakcija', style: text.titleMedium?.copyWith(color: cs.onSurface))),
                    if (_txs.isNotEmpty)
                      Text('${_txs.length}', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 8),
                  if (_txs.isEmpty)
                    _EmptyState(label: 'Nema transakcija za ovaj token')
                  else
                    ..._txs.map((t) => _TxRow(tx: t)).toList(),

                  const SizedBox(height: 8),
                  if (!_loadingMore)
                    Center(
                      child: TextButton(
                        onPressed: _before == null ? null : () => _loadMore(reset: false),
                        child: Text(_before == null ? 'Nema više' : 'Učitaj više', style: text.labelLarge?.copyWith(color: cs.primary)),
                      ),
                    )
                  else
                    const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator.adaptive())),

                  const SizedBox(height: 20),

                  // Token Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.info_outline, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Informacije o tokenu', style: text.titleMedium?.copyWith(color: cs.onSurface)),
                        const Spacer(),
                        if (_token.isNative)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: cs.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)), child: Text('Native Solana Token', style: text.labelSmall?.copyWith(color: cs.secondary))),
                      ]),
                      const SizedBox(height: 12),
                      if (!_token.isNative) ...[
                        _kv('Mint adresa', _token.mint ?? '—', copyKey: 'Mint adresa'),
                        const SizedBox(height: 8),
                      ],
                      _kv('Decimali', decimals.toString()),
                      const SizedBox(height: 8),
                      _kv('Token program', SolanaConstants.tokenProgram),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final url = _token.isNative
                                ? 'https://explorer.solana.com/address/${_wallet?.publicKey ?? ''}${SolanaConstants.isMainnet ? '' : '?cluster=devnet'}'
                                : 'https://explorer.solana.com/address/${_token.mint}${SolanaConstants.isMainnet ? '' : '?cluster=devnet'}';
                            _copy(url, 'Link');
                          },
                          icon: Icon(Icons.open_in_new, color: cs.primary),
                          label: Text('Otvori u Exploreru', style: text.labelLarge?.copyWith(color: cs.primary)),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _kv(String k, String v, {String? copyKey}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
      child: Row(children: [
        Expanded(child: Text(k, style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
        Expanded(
          flex: 2,
          child: Row(children: [
            Expanded(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: cs.onSurface))),
            if (copyKey != null)
              IconButton(onPressed: () => _copy(v, copyKey), icon: Icon(Icons.copy, color: cs.primary, size: 18)),
          ]),
        ),
      ]),
    );
  }
}

class _TxRow extends StatelessWidget {
  final TransactionModel tx;
  const _TxRow({required this.tx});

  IconData _iconForTx(TransactionModel t) {
    switch (t.type) {
      case TransactionType.send:
        return Icons.north_east;
      case TransactionType.receive:
        return Icons.south_west;
      case TransactionType.swap:
        return Icons.swap_horiz;
      case TransactionType.unknown:
        return Icons.hourglass_bottom;
    }
  }

  Color _colorForTx(BuildContext context, TransactionModel t) {
    final cs = Theme.of(context).colorScheme;
    switch (t.type) {
      case TransactionType.send:
        return cs.error;
      case TransactionType.receive:
        return cs.inversePrimary;
      case TransactionType.swap:
        return cs.primary;
      case TransactionType.unknown:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final decimals = tx.token.decimals;
    final scale = math.pow(10, decimals).toDouble();
    final amountUi = tx.amount.toDouble() / scale;
    final symbol = tx.token.symbol;
    final sign = tx.type == TransactionType.send ? '-' : '+';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(_iconForTx(tx), color: _colorForTx(context, tx))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tx.type == TransactionType.send
                  ? 'Slanje'
                  : tx.type == TransactionType.receive
                      ? 'Primanje'
                      : tx.type == TransactionType.swap
                          ? 'Zamjena'
                          : 'Transakcija',
              style: text.titleSmall?.copyWith(color: cs.onSurface),
            ),
            Text(Formatters.shortAddress(tx.isOutgoing ? tx.toAddress : tx.fromAddress), style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$sign${amountUi.toStringAsFixed(4)} $symbol', style: text.labelLarge?.copyWith(color: cs.onSurface)),
          Text(tx.formattedDateTime, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
