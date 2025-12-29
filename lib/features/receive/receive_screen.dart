import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:domovina_wallet/theme.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final GlobalKey _qrKey = GlobalKey();
  WalletModel? _activeWallet;
  List<TokenBalance> _tokens = const [];
  TokenBalance? _selectedToken; // Optional SPL mint to include
  bool _loading = true;
  late final SolanaRpcService _rpc;

  @override
  void initState() {
    super.initState();
    _rpc = SolanaRpcService.forCurrentCluster();
    _load();
  }

  @override
  void dispose() {
    _rpc.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final wallets = await SecureStorageService.instance.getWalletList();
      if (wallets.isEmpty) {
        if (!mounted) return;
        context.go(AppRoutes.onboarding);
        return;
      }
      final active = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      List<TokenBalance> tokens = const [];
      try {
        tokens = await _rpc.getTokenAccounts(active.publicKey);
        // Merge watched tokens without on-chain account yet
        final watched = await SecureStorageService.instance.getWatchedTokens(walletId: active.id);
        final existingMints = tokens.where((t) => t.mint != null).map((t) => t.mint!.toLowerCase()).toSet();
        for (final w in watched) {
          final mint = (w['mint'] as String?)?.toLowerCase();
          if (mint == null || existingMints.contains(mint)) continue;
          final decimals = (w['decimals'] as num?)?.toInt() ?? (TokenRegistry.decimalsForMint(mint) ?? 0);
          final info = TokenRegistry.byMint(mint);
          tokens.add(TokenBalance(
            mint: mint,
            symbol: info?.symbol ?? '',
            name: info?.symbol ?? 'Token',
            balance: BigInt.zero,
            decimals: decimals,
            iconUrl: null,
            isNative: false,
          ));
        }
        tokens.sort((a, b) => a.symbol.compareTo(b.symbol));
      } catch (e) {
        debugPrint('ReceiveScreen: failed to load tokens: $e');
      }

      if (!mounted) return;
      setState(() {
        _activeWallet = active;
        _tokens = tokens.where((t) => !t.isNative).toList(growable: false);
        _selectedToken = null; // Default: SOL address only
        _loading = false;
      });
    } catch (e) {
      debugPrint('ReceiveScreen: load error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri učitavanju.')));
      setState(() => _loading = false);
    }
  }

  String get _qrData {
    final address = _activeWallet?.publicKey ?? '';
    if (address.isEmpty) return '';
    // Solana Pay URI with optional spl-token
    if (_selectedToken != null && _selectedToken!.mint != null && _selectedToken!.mint!.isNotEmpty) {
      return 'solana:$address?spl-token=${_selectedToken!.mint}';
    }
    // Basic address-only payload
    return address;
  }

  Future<void> _copyAddress() async {
    final addr = _activeWallet?.publicKey;
    if (addr == null || addr.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: addr));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopirano!')));
  }

  Future<void> _shareAddress() async {
    final addr = _activeWallet?.publicKey;
    if (addr == null || addr.isEmpty) return;
    final tokenNote = _selectedToken?.symbol.isNotEmpty == true ? ' (za ${_selectedToken!.symbol})' : '';
    final text = 'Moja Solana adresa$tokenNote:\n$addr';
    await Share.share(text, subject: 'DOMOVINA Wallet adresa');
  }

  Future<void> _shareQrImage() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final xfile = XFile.fromData(pngBytes, mimeType: 'image/png', name: 'domovina_wallet_qr.png');
      await Share.shareXFiles([xfile], text: 'Moja Solana adresa: ${_activeWallet?.publicKey ?? ''}');
    } catch (e) {
      debugPrint('ReceiveScreen: share QR failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neuspješno dijeljenje QR koda')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Primi')),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final fullAddr = _activeWallet?.publicKey ?? '';
    final shortAddr = fullAddr.isEmpty ? '' : Formatters.shortAddress(fullAddr, head: 6, tail: 6);

    return Scaffold(
      appBar: AppBar(title: const Text('Primi')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // QR Section with Croatian flag border
          Center(
            child: _QrFlagFrame(
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  width: 280,
                  height: 280,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white, // Ensures maximum contrast for QR
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: cs.onSurface),
                    dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: cs.onSurface),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Address display and copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Adresa', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(fullAddr, style: text.bodySmall?.copyWith(color: cs.onSurface, fontFamily: 'RobotoMono', height: 1.4)),
                ]),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _copyAddress,
                icon: Icon(Icons.copy_rounded, color: cs.primary),
                tooltip: 'Kopiraj',
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Token selector (optional)
          if (_tokens.isNotEmpty) ...[
            Text('Token (opcionalno)', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            DropdownButtonFormField<TokenBalance?>
              (
                value: _selectedToken,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 1.4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                hint: Text('Odaberi token', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                items: [
                  const DropdownMenuItem<TokenBalance?>(value: null, child: Text('Samo SOL adresa')),
                  ..._tokens.map((t) => DropdownMenuItem<TokenBalance?>(
                        value: t,
                        child: Row(children: [
                          Icon(Icons.token, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${t.symbol.isEmpty ? 'Token' : t.symbol} — ${t.name}', overflow: TextOverflow.ellipsis)),
                        ]),
                      )),
                ],
                onChanged: (val) => setState(() => _selectedToken = val),
              ),
            const SizedBox(height: 16),
          ],

          // Instructions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.qr_code_2, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Skenirajte ovaj kod ili kopirajte adresu', style: text.bodyMedium?.copyWith(color: cs.onSurface))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.warning_amber_rounded, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(child: Text('Šaljite samo Solana (SOL) tokene', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          // Share buttons
          Row(children: [
            Expanded(child: AppButton(label: 'Podijeli adresu', icon: Icons.share, onPressed: _shareAddress)),
            const SizedBox(width: 12),
            Expanded(child: AppButton(label: 'Podijeli QR', icon: Icons.qr_code_2, onPressed: _shareQrImage, secondary: true, useSecondaryAccent: true)),
          ]),
          const SizedBox(height: 8),
          Center(child: Text(shortAddr, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _QrFlagFrame extends StatelessWidget {
  final Widget child;
  const _QrFlagFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.secondary, Colors.white, cs.primary], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
        ),
        child: child,
      ),
    );
  }
}
