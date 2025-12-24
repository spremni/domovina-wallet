import 'dart:async';
import 'dart:math' as math;

import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/core/utils/validators.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:domovina_wallet/features/send/widgets/confirm_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final _amountFocus = FocusNode();

  WalletModel? _wallet;
  TokenBalance? _sol;
  List<TokenBalance> _tokens = const [];
  TokenBalance? _selected;

  String? _addressError;
  String? _amountError;
  String? _addressAbbrev;
  bool _loading = true;
  bool _busy = false;

  // Approximate network fee for simple transfer
  static final BigInt _feeLamports = BigInt.from(5000); // ~0.000005 SOL

  late final SolanaRpcService _rpc;

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    scheduleMicrotask(_load);
    _addressCtrl.addListener(_validateAddressLive);
    _amountCtrl.addListener(_validateAmountLive);
  }

  @override
  void dispose() {
    _rpc.close();
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    _addressFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final wallets = await SecureStorageService.instance.getWalletList();
      if (wallets.isEmpty) {
        if (!mounted) return;
        context.go(AppRoutes.onboarding);
        return;
      }
      final active = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      final pubkey = active.publicKey;

      final balanceF = _rpc.getBalance(pubkey);
      final tokensF = _rpc.getTokenAccounts(pubkey);
      final results = await Future.wait([balanceF, tokensF]);
      final lamports = results[0] as BigInt;
      final spl = (results[1] as List<TokenBalance>)..removeWhere((t) => t.isNative);
      final sol = TokenBalance.nativeSolFromLamports(lamports);

      if (!mounted) return;
      setState(() {
        _wallet = active;
        _sol = sol;
        _tokens = List.unmodifiable(spl);
        _selected = _selected ?? _sol; // default to SOL
        _loading = false;
      });
    } catch (e) {
      debugPrint('SendScreen _load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri učitavanju podataka.')));
    }
  }

  // --------------------------------- Validation ---------------------------------
  void _validateAddressLive() {
    final text = _addressCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _addressError = null;
        _addressAbbrev = null;
      });
      return;
    }
    final ok = Validators.isValidSolanaAddress(text);
    setState(() {
      _addressError = ok ? null : 'Neispravna adresa';
      _addressAbbrev = ok ? Formatters.shortAddress(text) : null;
    });
  }

  void _validateAmountLive() {
    final text = _amountCtrl.text.replaceAll(',', '.').trim();
    if (text.isEmpty) {
      setState(() => _amountError = null);
      return;
    }
    final token = _selected;
    if (token == null) return;
    final ok = Validators.isValidAmount(text);
    if (!ok) {
      setState(() => _amountError = 'Neispravan iznos');
      return;
    }
    final sendBase = _parseUiToBase(text, token.decimals);
    final maxBase = _maxSendAmountBase(token);
    setState(() => _amountError = sendBase > maxBase ? 'Iznos premašuje dostupno' : null);
  }

  BigInt _maxSendAmountBase(TokenBalance token) {
    if (token.isNative) {
      final bal = token.balance;
      final remain = bal - _feeLamports;
      return remain > BigInt.zero ? remain : BigInt.zero;
    }
    return token.balance; // token transfer fee is in SOL; assume user has SOL
  }

  double _maxSendAmountUi(TokenBalance token) {
    final base = _maxSendAmountBase(token);
    final scale = math.pow(10, token.decimals).toDouble();
    return base.toDouble() / scale;
  }

  BigInt _parseUiToBase(String input, int decimals) {
    final s = input.trim().replaceAll(',', '.');
    if (!s.contains('.')) {
      return BigInt.tryParse(s) != null ? BigInt.parse(s) * BigInt.from(math.pow(10, decimals).toInt()) : BigInt.zero;
    }
    final parts = s.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    var frac = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
    if (frac.length > decimals) frac = frac.substring(0, decimals);
    final pad = decimals - frac.length;
    final full = intPart + frac + '0' * pad;
    return BigInt.tryParse(full) ?? BigInt.zero;
  }

  String _formatUi(double value, {required int decimals, int maxFraction = 6}) {
    final d = math.min(decimals, maxFraction).clamp(0, 9);
    return value.toStringAsFixed(d);
  }

  // --------------------------------- Actions ---------------------------------
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      _addressCtrl.text = text;
      _addressFocus.unfocus();
    } catch (e) {
      debugPrint('Clipboard paste failed: $e');
    }
  }

  void _openQrScanner() => context.push(AppRoutes.scan);

  void _pickToken() async {
    final picked = await showModalBottomSheet<TokenBalance>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (ctx) {
        final all = [if (_sol != null) _sol!, ..._tokens];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 48, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Text('Odaberi token', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: all.length,
                  itemBuilder: (c, i) {
                    final t = all[i];
                    return _TokenRow(
                      token: t,
                      selected: _selected == t,
                      onTap: () => Navigator.of(ctx).pop(t),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selected = picked;
      });
      _validateAmountLive();
    }
  }

  void _setMax() {
    final token = _selected;
    if (token == null) return;
    final maxUi = _maxSendAmountUi(token);
    if (maxUi <= 0) {
      setState(() => _amountError = 'Nedovoljno sredstava');
      return;
    }
    _amountCtrl.text = _formatUi(maxUi, decimals: token.decimals);
    _amountFocus.unfocus();
  }

  bool get _isFormValid {
    final addrOk = Validators.isValidSolanaAddress(_addressCtrl.text.trim());
    final tok = _selected;
    if (!addrOk || tok == null) return false;
    final text = _amountCtrl.text.trim();
    if (!Validators.isValidAmount(text)) return false;
    final base = _parseUiToBase(text, tok.decimals);
    if (base <= BigInt.zero) return false;
    return base <= _maxSendAmountBase(tok);
  }

  void _review() {
    final tok = _selected;
    if (tok == null) return;
    final addr = _addressCtrl.text.trim();
    final baseAmount = _parseUiToBase(_amountCtrl.text.replaceAll(',', '.'), tok.decimals);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (ctx) => ConfirmTransactionSheet(
        wallet: _wallet!,
        token: tok,
        recipientAddress: addr,
        amountBase: baseAmount,
        feeLamports: _feeLamports,
      ),
    );
  }

  // --------------------------------- UI ---------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Pošalji')), body: const Center(child: CircularProgressIndicator.adaptive()));
    }

    final token = _selected ?? _sol;
    final availableUi = token == null ? 0.0 : token.uiAmount;
    final symbol = token == null
        ? 'SOL'
        : token.symbol.isEmpty
            ? (token.isNative ? 'SOL' : '')
            : token.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Pošalji')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Recipient
          Text('Prima', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _Card(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _addressCtrl,
                  focusNode: _addressFocus,
                  decoration: InputDecoration(
                    hintText: 'Adresa primatelja',
                    hintStyle: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    border: InputBorder.none,
                  ),
                  style: text.bodyLarge?.copyWith(color: cs.onSurface),
                  autocorrect: false,
                ),
              ),
              IconButton(icon: Icon(Icons.paste, color: cs.primary), onPressed: _pasteFromClipboard),
              IconButton(icon: Icon(Icons.qr_code_scanner, color: cs.primary), onPressed: _openQrScanner),
            ]),
          ),
          if (_addressError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(_addressError!, style: text.labelSmall?.copyWith(color: cs.error)),
            )
          else if (_addressAbbrev != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(_addressAbbrev!, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),

          const SizedBox(height: 16),

          // Token selection
          Text('Token', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickToken,
            borderRadius: BorderRadius.circular(12),
            child: _Card(
              child: Row(children: [
                _TokenIcon(token: token),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(symbol, style: text.titleMedium?.copyWith(color: cs.onSurface)),
                    Text(token?.name ?? 'Token', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text('Bal: ${availableUi.toStringAsFixed(6)}', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down, color: cs.onSurface),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          // Amount section
          Text('Iznos', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _Card(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  focusNode: _amountFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))],
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: text.displaySmall?.copyWith(color: cs.onSurfaceVariant),
                    border: InputBorder.none,
                  ),
                  style: text.displaySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1)),
                child: Text(symbol, style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _setMax, child: Text('Max', style: text.labelLarge?.copyWith(color: cs.secondary))),
            ]),
          ),
          if (_amountError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(_amountError!, style: text.labelSmall?.copyWith(color: cs.error)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Row(children: [
                Text('≈ € —', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text('Dostupno: ${availableUi.toStringAsFixed(6)} $symbol', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),

          const SizedBox(height: 16),

          // Fee
          _Card(
            child: Row(children: [
              Icon(Icons.receipt_long, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text('Naknada mreže: ~0.000005 SOL', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ),

          const SizedBox(height: 20),

          AppButton(label: 'Pregledaj transakciju', icon: Icons.arrow_forward, onPressed: _isFormValid && !_busy ? _review : null),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ------------------------------ Small UI pieces ------------------------------

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
      ),
      child: child,
    );
  }
}

class _TokenRow extends StatelessWidget {
  final TokenBalance token;
  final bool selected;
  final VoidCallback onTap;
  const _TokenRow({required this.token, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final symbol = token.symbol.isEmpty ? (token.isNative ? 'SOL' : '') : token.symbol;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.1), width: 0.5))),
        child: Row(children: [
          _TokenIcon(token: token),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(symbol.isEmpty ? 'Token' : symbol, style: text.titleSmall?.copyWith(color: cs.onSurface)),
              Text(token.name, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(token.uiAmount.toStringAsFixed(6), style: text.labelLarge?.copyWith(color: cs.onSurface)),
            if (selected) Text('Odabrano', style: text.labelSmall?.copyWith(color: cs.primary)),
          ]),
        ]),
      ),
    );
  }
}

class _TokenIcon extends StatelessWidget {
  final TokenBalance? token;
  const _TokenIcon({required this.token});

  IconData _iconForToken(TokenBalance? t) {
    if (t == null) return Icons.token;
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
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(_iconForToken(token), color: cs.primary),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
        Text(value, style: text.labelLarge?.copyWith(color: cs.onSurface)),
      ]),
    );
  }
}
