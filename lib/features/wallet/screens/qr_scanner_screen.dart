import 'dart:async';

import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/core/utils/validators.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:domovina_wallet/features/send/send_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _torchOn = false;
  bool _handling = false;
  bool _permissionGranted = kIsWeb; // On web, let the widget handle permission prompt
  bool _permissionPermanentlyDenied = false;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    scheduleMicrotask(_ensurePermission);
    // No torch state stream available; we'll optimistically toggle state on tap.
  }

  Future<void> _ensurePermission() async {
    if (kIsWeb) return; // browser will prompt
    try {
      var status = await ph.Permission.camera.status;
      if (status.isGranted) {
        setState(() => _permissionGranted = true);
        return;
      }
      status = await ph.Permission.camera.request();
      if (status.isGranted) {
        setState(() => _permissionGranted = true);
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _permissionGranted = false;
          _permissionPermanentlyDenied = true;
        });
      } else {
        setState(() {
          _permissionGranted = false;
          _permissionPermanentlyDenied = false;
        });
      }
    } catch (e) {
      debugPrint('QR permission check failed: $e');
      setState(() => _permissionGranted = true); // fallback to try showing scanner
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    _controller.toggleTorch();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    _handling = true;
    HapticFeedback.mediumImpact();
    try {
      final handled = await _handleContent(code);
      if (!handled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neispravan QR kod')));
        _handling = false; // continue scanning
      }
    } catch (e) {
      debugPrint('QR handle error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri obradi QR koda')));
      _handling = false;
    }
  }

  Future<bool> _handleContent(String text) async {
    // Valid Solana address?
    if (Validators.isValidSolanaAddress(text)) {
      if (!mounted) return true;
      context.push(AppRoutes.send, extra: SendScreenArgs(recipient: text));
      return true;
    }
    // URI schemes
    Uri? uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {}
    if (uri != null && uri.scheme.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      // Solana Pay or DOMOVINAPay-style links
      if (scheme == 'solana' || scheme == 'domovina' || scheme == 'domovinapay') {
        if (!mounted) return true;
        context.push(AppRoutes.pay, extra: text);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // Camera preview
          if (_permissionGranted)
            Positioned.fill(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            )
          else
            Positioned.fill(child: _PermissionView(onRetry: _ensurePermission, permanentlyDenied: _permissionPermanentlyDenied)),

          // Overlay shading and scanning frame
          Positioned.fill(child: _ScannerOverlay(animation: _anim)),

          // Header controls
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Row(children: [
              _RoundIconButton(icon: Icons.arrow_back, onPressed: () => context.pop()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Skeniraj QR kod', style: text.labelLarge?.copyWith(color: Colors.white)),
                ]),
              ),
              const Spacer(),
              _RoundIconButton(
                icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                onPressed: _toggleTorch,
              ),
            ]),
          ),

          // Instructions
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Usmjerite kameru prema QR kodu', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Adresu ćemo prepoznati automatski', textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: Colors.white)),
        ),
      );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final size = w < h ? w * 0.72 : h * 0.52; // square frame
      final left = (w - size) / 2;
      final top = (h - size) / 2;
      return Stack(children: [
        // Dimmed background
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ),
        // Clear cutout
        Positioned.fromRect(
          rect: Rect.fromLTWH(left, top, size, size),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ),
        // Animated corners
        Positioned.fromRect(rect: Rect.fromLTWH(left, top, size, size), child: _CornerPainter(anim: animation)),
      ]);
    });
  }
}

class _CornerPainter extends StatefulWidget {
  const _CornerPainter({required this.anim});
  final Animation<double> anim;
  @override
  State<_CornerPainter> createState() => _CornerPainterState();
}

class _CornerPainterState extends State<_CornerPainter> {
  @override
  void initState() {
    super.initState();
    widget.anim.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CornersPainter(progress: widget.anim.value),
      child: const SizedBox.expand(),
    );
  }
}

class _CornersPainter extends CustomPainter {
  _CornersPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const double corner = 26;
    final double len = 22 + 12 * progress;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(0, corner), Offset(0, corner - len), paint);
    canvas.drawLine(Offset(corner, 0), Offset(corner - len, 0), paint);

    // Top-right
    canvas.drawLine(Offset(size.width, corner), Offset(size.width, corner - len), paint);
    canvas.drawLine(Offset(size.width - corner, 0), Offset(size.width - corner + len, 0), paint);

    // Bottom-left
    canvas.drawLine(Offset(0, size.height - corner), Offset(0, size.height - corner + len), paint);
    canvas.drawLine(Offset(corner, size.height), Offset(corner - len, size.height), paint);

    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height - corner), Offset(size.width, size.height - corner + len), paint);
    canvas.drawLine(Offset(size.width - corner, size.height), Offset(size.width - corner + len, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) => oldDelegate.progress != progress;
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.onRetry, required this.permanentlyDenied});
  final VoidCallback onRetry;
  final bool permanentlyDenied;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.camera_alt, color: Colors.white.withValues(alpha: 0.9), size: 48),
        const SizedBox(height: 12),
        Text('Dopustite pristup kameri', style: text.titleLarge?.copyWith(color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Za skeniranje QR koda potrebna je dozvola za kameru.', style: text.bodyMedium?.copyWith(color: Colors.white70), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (!permanentlyDenied)
          FilledButton(onPressed: onRetry, child: const Text('Dodijeli dozvolu'))
        else
          Column(children: [
            TextButton(onPressed: onRetry, child: const Text('Pokušaj ponovno')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await ph.openAppSettings();
              },
              child: const Text('Otvori postavke'),
            ),
          ]),
      ]),
    );
  }
}

// (old placeholder removed)
