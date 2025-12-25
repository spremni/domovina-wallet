import 'dart:async';
import 'dart:typed_data';

import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/services/crypto_service.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:domovina_wallet/services/solana_tx_builder.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/features/send/screens/transaction_result_screen.dart';

class ConfirmTransactionSheet extends StatefulWidget {
  final WalletModel wallet;
  final TokenBalance token;
  final String recipientAddress;
  /// Amount in base units (lamports for SOL or token base units)
  final BigInt amountBase;
  /// Network fee estimate in lamports (used for UI only)
  final BigInt feeLamports;

  const ConfirmTransactionSheet({super.key, required this.wallet, required this.token, required this.recipientAddress, required this.amountBase, required this.feeLamports});

  @override
  State<ConfirmTransactionSheet> createState() => _ConfirmTransactionSheetState();
}

class _ConfirmTransactionSheetState extends State<ConfirmTransactionSheet> {
  bool _biometricsEnabled = false;
  bool _submitting = false;
  String? _error;
  late final SolanaRpcService _rpc;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    scheduleMicrotask(_loadPrefs);
  }

  @override
  void dispose() {
    _rpc.close();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final enabled = await SecureStorageService.instance.getBiometricsEnabled();
      if (!mounted) return;
      setState(() => _biometricsEnabled = enabled);
    } catch (e) {
      debugPrint('ConfirmSheet: biometrics pref read error: $e');
    }
  }

  String get _tokenSymbol => widget.token.symbol.isEmpty ? (widget.token.isNative ? 'SOL' : '') : widget.token.symbol;

  String get _recipientShort => Formatters.shortAddress(widget.recipientAddress);

  bool get _isHighValue {
    // Simple threshold for SOL; for SPL skip for now
    if (widget.token.isNative) {
      final ui = widget.amountBase.toDouble() / Formatters.lamportsPerSol;
      return ui >= 10.0; // ~10 SOL threshold
    }
    return false;
  }

  Future<bool> _authenticateIfNeeded() async {
    if (!_biometricsEnabled) return true;
    if (kIsWeb) return true; // not supported on web
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      if (!supported || !can) return true; // fallback to device lock screen on send
      final ok = await _auth.authenticate(
        localizedReason: 'Potvrdite slanje transakcije',
        options: const AuthenticationOptions(stickyAuth: true, useErrorDialogs: true),
      );
      return ok;
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!widget.token.isNative) {
      setState(() => _error = 'Slanje SPL tokena još nije podržano u ovoj verziji.');
      return;
    }
    final authed = await _authenticateIfNeeded();
    if (!authed) {
      setState(() => _error = 'Autentikacija nije uspjela.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Load sender secret key
      final sk = await SecureStorageService.instance.getPrivateKey(walletId: widget.wallet.id);
      if (sk == null) {
        throw Exception('Nedostaje privatni ključ.');
      }

      // Get recent blockhash
      final blockhash = await _rpc.getRecentBlockhash();

      // Build and sign transfer transaction (native SOL)
      final signedBase64 = await SolanaTxBuilder.buildAndSignSystemTransfer(
        fromPublicKeyBase58: widget.wallet.publicKey,
        fromSecretKey64: sk,
        toPublicKeyBase58: widget.recipientAddress,
        lamports: widget.amountBase,
        recentBlockhashBase58: blockhash,
        signer: CryptoService.instance.signTransaction,
      );

      // Submit
      final signature = await _rpc.sendTransaction(signedBase64);

      if (!mounted) return;
      // Close sheet and navigate to Transaction Result (success)
      Navigator.of(context).pop();
      final args = TransactionResultArgs(
        success: true,
        recipientAddress: widget.recipientAddress,
        amountBase: widget.amountBase,
        token: widget.token,
        signature: signature,
      );
      context.push(AppRoutes.txResult, extra: args);
    } catch (e) {
      debugPrint('Submit tx failed: $e');
      if (!mounted) return;
      // Close sheet and navigate to Transaction Result (failure)
      Navigator.of(context).pop();
      final args = TransactionResultArgs(
        success: false,
        recipientAddress: widget.recipientAddress,
        amountBase: widget.amountBase,
        token: widget.token,
        rawError: e.toString(),
      );
      context.push(AppRoutes.txResult, extra: args);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final amountUi = widget.token.isNative
        ? widget.amountBase.toDouble() / Formatters.lamportsPerSol
        : widget.amountBase.toDouble() / (BigInt.from(10).pow(widget.token.decimals).toDouble());
    final feeUi = widget.feeLamports.toDouble() / Formatters.lamportsPerSol;
    final totalUi = widget.token.isNative ? amountUi + feeUi : amountUi; // SPL fee is separate in SOL

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(child: Text('Potvrdi transakciju', style: tt.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),

          // Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.15))),
            child: Column(children: [
              _Row(label: 'Šaljem', value: '${amountUi.toStringAsFixed(widget.token.isNative ? 6 : (widget.token.decimals > 6 ? 6 : widget.token.decimals))} ${_tokenSymbol.isEmpty ? '' : _tokenSymbol}'),
              _Row(label: 'Prima', value: _recipientShort),
              _Row(label: 'Naknada', value: '~${feeUi.toStringAsFixed(6)} SOL'),
              Divider(color: cs.outline.withValues(alpha: 0.2), height: 16),
              _Row(label: 'Ukupno', value: widget.token.isNative ? '${totalUi.toStringAsFixed(6)} SOL' : '${amountUi.toStringAsFixed(6)} ${_tokenSymbol}'),
            ]),
          ),

          const SizedBox(height: 12),

          // Warnings
          if (_isHighValue)
            _Warning(text: 'Visok iznos — provjerite adresu prije potvrde'),

          const SizedBox(height: 8),

          // Biometrics indicator
          if (_biometricsEnabled)
            Row(children: [
              Icon(Icons.fingerprint_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Biometrijska potvrda je uključena', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
            ]),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: tt.labelSmall?.copyWith(color: cs.error)),
          ],

          const SizedBox(height: 12),

          // Actions
          AppButton(label: 'Potvrdi i pošalji', icon: Icons.send_rounded, onPressed: _submitting ? null : _submit),
          const SizedBox(height: 6),
          Center(
            child: TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: Text('Odustani', style: tt.titleSmall?.copyWith(color: cs.onSurface))),
          ),

          if (_submitting) ...[
            const SizedBox(height: 10),
            Center(child: CircularProgressIndicator.adaptive(backgroundColor: cs.primary.withValues(alpha: 0.2))),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
        Text(value, style: tt.labelLarge?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  const _Warning({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 1)),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: cs.error),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: tt.bodySmall?.copyWith(color: cs.error))),
      ]),
    );
  }
}
