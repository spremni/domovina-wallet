import 'dart:async';

import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:solana/base58.dart' show base58decode;

class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({super.key});

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  late final SolanaRpcService _rpc;
  WalletModel? _activeWallet;
  bool _loading = true;
  bool _searching = false;
  String? _error;

  // Search result
  MintInfo? _mintInfo;
  String? _searchedMint;
  bool _alreadyAdded = false;
  Set<String> _existingMints = {};
  List<Map<String, dynamic>> _watched = const [];

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    scheduleMicrotask(_bootstrap);
  }

  @override
  void dispose() {
    _rpc.close();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final wallets = await SecureStorageService.instance.getWalletList();
      if (wallets.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nema aktivnog walleta.')));
        return;
      }
      final active = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      final watched = await SecureStorageService.instance.getWatchedTokens(walletId: active.id);
      // Build existing mints set from chain + watched will be checked on-demand
      final tokenAccounts = await _rpc.getTokenAccounts(active.publicKey);
      final onChainMints = tokenAccounts.where((t) => t.mint != null).map((t) => t.mint!.toLowerCase());
      setState(() {
        _activeWallet = active;
        _watched = watched;
        _existingMints = {...onChainMints, ...watched.map((e) => (e['mint'] as String).toLowerCase())};
        _loading = false;
      });
    } catch (e) {
      debugPrint('AddTokenScreen bootstrap error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri učitavanju.')));
    }
  }

  bool _isValidAddress(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    try {
      final decoded = base58decode(s);
      return decoded.length == 32; // mint/pubkey should be 32 bytes
    } catch (_) {
      return false;
    }
  }

  Future<void> _onSearch() async {
    final query = _controller.text.trim();
    setState(() {
      _error = null;
      _searchedMint = null;
      _mintInfo = null;
      _alreadyAdded = false;
    });
    if (!_isValidAddress(query)) {
      setState(() => _error = 'Neispravna adresa (Base58, 32 bajta)');
      return;
    }
    setState(() => _searching = true);
    try {
      final info = await _rpc.getMintInfo(query);
      if (info == null) {
        setState(() => _error = 'Token nije pronađen na lancu');
        return;
      }
      final exists = _existingMints.contains(query.toLowerCase());
      setState(() {
        _searchedMint = query;
        _mintInfo = info;
        _alreadyAdded = exists;
      });
    } catch (e) {
      debugPrint('AddTokenScreen search error: $e');
      setState(() => _error = 'Greška pri dohvaćanju tokena');
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _addToken(String mint, {MintInfo? info}) async {
    final wallet = _activeWallet;
    if (wallet == null) return;
    final lower = mint.toLowerCase();
    if (_existingMints.contains(lower)) {
      setState(() => _alreadyAdded = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token je već dodan.')));
      return;
    }
    // Check if ATA exists; if not, inform the user (creation will be supported later)
    try {
      final accounts = await _rpc.getOwnerTokenAccountsForMint(wallet.publicKey, mint);
      if (accounts.isEmpty) {
        debugPrint('ATA missing for $mint and owner ${wallet.publicKey}. Will be created on first use.');
      }
    } catch (e) {
      debugPrint('getOwnerTokenAccountsForMint failed: $e');
    }

    // Prepare watched token entry
    final reg = TokenRegistry.byMint(mint);
    final decimals = info?.decimals ?? (TokenRegistry.decimalsForMint(mint) ?? 0);
    final entry = <String, dynamic>{
      'mint': mint,
      'decimals': decimals,
      if (reg != null) 'symbol': reg.symbol,
      if (reg != null) 'name': reg.symbol,
    };
    try {
      await SecureStorageService.instance.upsertWatchedToken(walletId: wallet.id, token: entry);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token dodan.')));
      context.pop();
    } catch (e) {
      debugPrint('Failed to save watched token: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spremanje nije uspjelo.')));
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _controller.text = text;
        _focusNode.requestFocus();
      }
    } catch (e) {
      debugPrint('Clipboard paste failed: $e');
    }
  }

  List<TokenInfo> get _popularTokens {
    final all = TokenRegistry.all();
    return all
        .where((t) => t.mint != null && t.mint != '<PLACEHOLDER_MINT>')
        .where((t) => !_existingMints.contains((t.mint!).toLowerCase()))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj token')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Search section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: text.bodyMedium?.copyWith(color: cs.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Mint adresa',
                              labelStyle: text.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                              hintText: 'Unesite SPL token mint',
                              hintStyle: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(onPressed: _pasteFromClipboard, icon: Icon(Icons.paste, color: cs.primary)),
                        _searching
                            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: cs.primary, strokeWidth: 2))
                            : IconButton(onPressed: _onSearch, icon: Icon(Icons.search, color: cs.primary)),
                      ]),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _InlineError(message: _error!),
                  ],

                  const SizedBox(height: 16),
                  Text('Popularni tokeni', style: text.titleMedium?.copyWith(color: cs.onSurface)),
                  const SizedBox(height: 8),
                  if (_popularTokens.isEmpty)
                    Text('Svi popularni tokeni su dodani', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _popularTokens)
                          ActionChip(
                            label: Text('${t.symbol}', style: text.labelLarge?.copyWith(color: cs.primary)),
                            avatar: Icon(Icons.token, color: cs.primary),
                            backgroundColor: cs.primary.withValues(alpha: 0.08),
                            side: BorderSide(color: cs.primary.withValues(alpha: 0.35), width: 1),
                            onPressed: () => _addToken(t.mint!),
                          ),
                      ],
                    ),

                  const SizedBox(height: 20),
                  if (_mintInfo != null && _searchedMint != null)
                    _MintResultCard(
                      mint: _searchedMint!,
                      info: _mintInfo!,
                      alreadyAdded: _alreadyAdded,
                      onAdd: () => _addToken(_searchedMint!, info: _mintInfo),
                    ),
                ],
              ),
            ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: cs.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: text.labelMedium?.copyWith(color: cs.error))),
      ]),
    );
  }
}

class _MintResultCard extends StatelessWidget {
  final String mint;
  final MintInfo info;
  final bool alreadyAdded;
  final VoidCallback onAdd;
  const _MintResultCard({required this.mint, required this.info, required this.alreadyAdded, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reg = TokenRegistry.byMint(mint);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.token, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reg?.symbol ?? 'SPL Token', style: text.titleMedium?.copyWith(color: cs.onSurface)),
              Text('${reg?.symbol ?? 'Token'} • Decimals: ${info.decimals}', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text('Mint: $mint', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (alreadyAdded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.secondary.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(children: [
              Icon(Icons.check_circle, color: cs.secondary),
              const SizedBox(width: 8),
              Expanded(child: Text('Već dodano', style: text.labelMedium?.copyWith(color: cs.secondary))),
            ]),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: Icon(Icons.add, color: cs.onPrimary),
              label: Text('Dodaj token', style: text.labelLarge?.copyWith(color: cs.onPrimary)),
              onPressed: onAdd,
            ),
          ),
        const SizedBox(height: 8),
        Text('Ako je potrebno, associated account bit će kreiran pri prvoj transakciji.', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
