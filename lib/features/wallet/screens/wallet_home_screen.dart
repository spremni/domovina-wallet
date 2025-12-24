import 'dart:async';
import 'dart:math' as math;

import 'package:domovina_wallet/core/constants/solana_constants.dart';
import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/transaction_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:domovina_wallet/theme.dart';
import 'package:domovina_wallet/features/wallet/screens/token_detail_screen.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:domovina_wallet/widgets/balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  WalletModel? _activeWallet;
  TokenBalance? _solBalance;
  List<TokenBalance> _tokens = const [];
  List<TransactionModel> _recentTxs = const [];
  bool _loading = true;
  bool _refreshing = false;
  late final SolanaRpcService _rpc;

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    // Load active wallet, then load data
    scheduleMicrotask(_loadActiveWallet);
  }

  @override
  void dispose() {
    _rpc.close();
    super.dispose();
  }

  Future<void> _loadActiveWallet() async {
    try {
      final wallets = await SecureStorageService.instance.getWalletList();
      if (wallets.isEmpty) {
        if (!mounted) return;
        context.go(AppRoutes.onboarding);
        return;
      }
      WalletModel active = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      setState(() => _activeWallet = active);
      await _refreshAll();
    } catch (e) {
      debugPrint('WalletHome: failed to load active wallet: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri učitavanju walleta.')));
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    final pubkey = _activeWallet?.publicKey;
    if (pubkey == null || pubkey.isEmpty) return;
    setState(() {
      _refreshing = true;
      _loading = false;
    });
    try {
      final balanceF = _rpc.getBalance(pubkey);
      final tokensF = _rpc.getTokenAccounts(pubkey);
      final sigsF = _rpc.getSignaturesForAddress(pubkey, limit: 10);

      final results = await Future.wait([balanceF, tokensF, sigsF]);
      final lamports = results[0] as BigInt;
      final splTokens = (results[1] as List<TokenBalance>)..sort((a, b) => a.symbol.compareTo(b.symbol));
      final sigs = results[2] as List<String>;

      final sol = TokenBalance.nativeSolFromLamports(lamports);
      final animatedFrom = _solBalance?.uiAmount ?? 0;
      final animatedTo = sol.uiAmount;

      // Fetch last 5 transactions details in parallel
      final subset = sigs.take(5).toList(growable: false);
      final txs = await Future.wait(
        subset.map((s) => _rpc.getTransaction(s, ownerAddress: pubkey)),
        eagerError: false,
      );
      final parsedTxs = txs.whereType<TransactionModel>().toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Merge watched tokens (tracked by user) that may not have on-chain accounts yet
      try {
        final wallets = await SecureStorageService.instance.getWalletList();
        final active = wallets.firstWhere((w) => w.id == _activeWallet?.id, orElse: () => wallets.first);
        final watched = await SecureStorageService.instance.getWatchedTokens(walletId: active.id);
        final existingMints = splTokens.where((t) => t.mint != null).map((t) => t.mint!.toLowerCase()).toSet();
        for (final w in watched) {
          final mint = (w['mint'] as String?)?.toLowerCase();
          if (mint == null || existingMints.contains(mint)) continue;
          final decimals = (w['decimals'] as num?)?.toInt() ?? (TokenRegistry.decimalsForMint(mint) ?? 0);
          final info = TokenRegistry.byMint(mint);
          splTokens.add(TokenBalance(
            mint: mint,
            symbol: info?.symbol ?? '',
            name: info?.symbol ?? 'Token',
            balance: BigInt.zero,
            decimals: decimals,
            iconUrl: null,
            isNative: false,
          ));
        }
      } catch (e) {
        debugPrint('WalletHome: merge watched tokens failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _solBalance = sol;
        _tokens = splTokens.where((t) => !t.isNative).toList(growable: false);
        _recentTxs = parsedTxs.take(5).toList(growable: false);
      });

      // BalanceCard animates internally on value change
    } catch (e) {
      debugPrint('WalletHome: refresh failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neuspješno osvježavanje podataka.')));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openSettings() => context.push(AppRoutes.settings);
  void _openScanner() => context.push(AppRoutes.scan);
  void _openSend() => context.push(AppRoutes.send);
  void _openReceive() => context.push(AppRoutes.receive);
  void _openPay() => context.push(AppRoutes.pay);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('DOMOVINA Wallet')),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final walletName = _activeWallet?.name ?? 'Wallet';
    final walletAddrShort = _activeWallet?.abbreviatedAddress ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            // Placeholder for multi-wallet switcher
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Više walleta uskoro')));
          },
          borderRadius: BorderRadius.circular(12),
          child: Row(children: [
            const SizedBox(width: 8),
            Icon(Icons.account_balance_wallet, color: cs.onSurface),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(walletName, style: text.titleMedium?.copyWith(color: cs.onSurface)),
              Text(walletAddrShort, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, color: cs.onSurface),
          ]),
        ),
        actions: [
          IconButton(icon: Icon(Icons.settings, color: cs.onSurface), onPressed: _openSettings),
          IconButton(icon: Icon(Icons.qr_code_scanner, color: cs.onSurface), onPressed: _openScanner),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _refreshAll,
        edgeOffset: 16,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            BalanceCard(
              balance: _solBalance?.balance ?? BigInt.zero,
              symbol: 'SOL',
              fiatValue: null,
              fiatCurrency: 'EUR',
              isLoading: _solBalance == null,
              onRefresh: _refreshAll,
            ),
            const SizedBox(height: 16),
            _ActionRow(onSend: _openSend, onReceive: _openReceive, onPay: _openPay, onScan: _openScanner),
            const SizedBox(height: 12),
            _SectionHeader(
              title: 'Tokeni',
              action: TextButton(
                onPressed: () async {
                  await context.push(AppRoutes.addToken);
                  // Refresh after returning from Add Token screen
                  await _refreshAll();
                },
                child: Text('Dodaj token', style: text.labelLarge?.copyWith(color: cs.primary)),
              ),
            ),
            const SizedBox(height: 8),
            if (_tokens.isEmpty)
              _EmptyState(label: 'Nema pronađenih tokena')
            else
              ..._tokens.map((t) => _TokenListItem(token: t)).toList(),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Nedavne transakcije',
              action: TextButton(
                onPressed: () => context.push(AppRoutes.history),
                child: Text('Vidi sve', style: text.labelLarge?.copyWith(color: cs.primary)),
              ),
            ),
            const SizedBox(height: 8),
            if (_recentTxs.isEmpty)
              _EmptyState(label: 'Nema nedavnih transakcija')
            else
              ..._recentTxs.map((tx) => _TxListItem(tx: tx)).toList(),
            const SizedBox(height: 24),
            if (_refreshing)
              Center(
                child: Text('Osvježavanje...', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                SolanaConstants.isMainnet ? 'Mainnet-beta' : 'Devnet',
                style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// Extracted BalanceCard moved to package:domovina_wallet/widgets/balance_card.dart

class _ActionRow extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onPay;
  final VoidCallback onScan;
  const _ActionRow({required this.onSend, required this.onReceive, required this.onPay, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget chip({required IconData icon, required String label, required VoidCallback onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Text(label, style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
        );

    return Row(children: [
      Expanded(child: chip(icon: Icons.arrow_upward, label: 'Pošalji', onTap: onSend)),
      const SizedBox(width: 10),
      Expanded(child: chip(icon: Icons.arrow_downward, label: 'Primi', onTap: onReceive)),
      const SizedBox(width: 10),
      Expanded(child: chip(icon: Icons.shopping_cart, label: 'Plati', onTap: onPay)),
      const SizedBox(width: 10),
      Expanded(child: chip(icon: Icons.qr_code, label: 'Skeniraj', onTap: onScan)),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(title, style: text.titleMedium?.copyWith(color: cs.onSurface))),
        if (action != null) action!,
      ],
    );
  }
}

class _TokenListItem extends StatelessWidget {
  final TokenBalance token;
  const _TokenListItem({required this.token});

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () {
        context.push(AppRoutes.tokenDetail, extra: TokenDetailArgs(token: token));
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_iconForToken(token), color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(token.symbol.isEmpty ? (token.mint?.substring(0, 6) ?? 'TOKEN') : token.symbol, style: text.titleMedium?.copyWith(color: cs.onSurface)),
              Text(token.name, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(token.formattedBalance(fractionDigits: token.decimals.clamp(0, 6)), style: text.labelLarge?.copyWith(color: cs.onSurface)),
            Text('≈ € —', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}

class _TxListItem extends StatelessWidget {
  final TransactionModel tx;
  const _TxListItem({required this.tx});

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
        return cs.error; // high-contrast for outgoing
      case TransactionType.receive:
        return cs.inversePrimary; // contrasting accent for incoming
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(_iconForTx(tx), color: _colorForTx(context, tx)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tx.type == TransactionType.send ? 'Slanje' : tx.type == TransactionType.receive ? 'Primanje' : tx.type == TransactionType.swap ? 'Zamjena' : 'Transakcija',
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
