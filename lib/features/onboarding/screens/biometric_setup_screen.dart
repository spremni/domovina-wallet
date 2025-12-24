import 'dart:io' show Platform;

import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

class BiometricSetupScreen extends StatefulWidget {
  const BiometricSetupScreen({super.key});

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> with SingleTickerProviderStateMixin {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _supported = false;
  bool _canCheck = false;
  bool _enabling = false;
  List<BiometricType> _biometrics = const [];

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
    _initSupport();
  }

  Future<void> _initSupport() async {
    bool supported = false;
    bool canCheck = false;
    List<BiometricType> types = const [];
    try {
      if (!kIsWeb) {
        supported = await _auth.isDeviceSupported();
        canCheck = await _auth.canCheckBiometrics;
        if (supported && canCheck) {
          types = await _auth.getAvailableBiometrics();
        }
      }
    } catch (e) {
      debugPrint('Biometrics support check failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _canCheck = canCheck;
      _biometrics = types;
    });
  }

  IconData _iconForBiometrics() {
    if (kIsWeb) return Icons.fingerprint_rounded;
    if (Platform.isIOS) {
      // Prefer face icon when face is available
      if (_biometrics.contains(BiometricType.face)) return Icons.face_rounded;
      return Icons.fingerprint_rounded;
    }
    return Icons.fingerprint_rounded;
  }

  Future<void> _enableBiometrics() async {
    setState(() => _enabling = true);
    try {
      final didAuth = await _auth.authenticate(
        localizedReason: 'Prijavite se biometrijom za zaštitu walleta',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true, useErrorDialogs: true),
      );
      if (!mounted) return;
      if (didAuth) {
        await SecureStorageService.instance.setBiometricsEnabled(true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biometrija uključena')));
        context.go(AppRoutes.home);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Autentikacija nije uspjela')));
      }
    } catch (e) {
      debugPrint('Biometric authenticate failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ne mogu pokrenuti biometrijsku autentikaciju')));
      }
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  Future<void> _skip() async {
    try {
      await SecureStorageService.instance.setBiometricsEnabled(false);
    } catch (e) {
      debugPrint('Failed to save biometrics disabled: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biometrija nije uključena. Manja sigurnost.')));
    context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final showEnable = _supported && _canCheck && _biometrics.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometrijska zaštita'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), color: cs.onSurface, onPressed: () => context.pop()),
      ),
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface, cs.surfaceContainerHighest.withValues(alpha: 0.2)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ScaleTransition(
              scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Icon(_iconForBiometrics(), size: 42, color: cs.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text('Zaštitite svoj wallet', style: tt.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Brzo i sigurno otključavanje pomoću Face ID/otiska prsta. Preporučeno za veću sigurnost.', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
            const Spacer(),
            if (!showEnable)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
                child: Row(children: [
                  Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(kIsWeb ? 'Biometrija nije podržana u web pregledniku. Možete nastaviti bez nje.' : 'Ovaj uređaj ne podržava biometriju ili nije postavljena.', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.9))))
                ]),
              ),
            const SizedBox(height: 12),
            if (showEnable)
              AppButton(label: 'Uključi biometriju', icon: Icons.verified_user_outlined, onPressed: _enabling ? null : _enableBiometrics, useSecondaryAccent: true),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _skip,
                child: Text('Preskoči', style: tt.titleSmall?.copyWith(color: cs.onSurface)),
              ),
            )
          ]),
        )
      ]),
    );
  }
}
