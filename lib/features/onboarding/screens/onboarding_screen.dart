import 'dart:async';

import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _pulseController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScaleIn;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _buttonsFade;
  late final Animation<Offset> _buttonsSlide;

  String _version = '';

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);

    _logoFade = CurvedAnimation(parent: _staggerController, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
    _logoScaleIn = CurvedAnimation(parent: _staggerController, curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack));
    _taglineFade = CurvedAnimation(parent: _staggerController, curve: const Interval(0.35, 0.6, curve: Curves.easeOut));
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _staggerController, curve: const Interval(0.35, 0.6, curve: Curves.easeOut)),
    );
    _buttonsFade = CurvedAnimation(parent: _staggerController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut));
    _buttonsSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _staggerController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );

    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'v${info.version}+${info.buildNumber}');
    } catch (e) {
      debugPrint('Failed to load app version: $e');
      if (!mounted) return;
      setState(() => _version = 'v1.0.0');
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              cs.surface.withValues(alpha: 0.95),
              cs.primaryContainer.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1.02).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
                    child: ScaleTransition(
                      scale: _logoScaleIn,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [cs.secondary, cs.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/Croatian_shield_checkerboard_minimal_logo_red__blue__white_1766532723985.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SlideTransition(
                  position: _taglineSlide,
                  child: FadeTransition(
                    opacity: _taglineFade,
                    child: Column(
                      children: [
                        Text('DOMOVINA Wallet', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Vaš ključ do slobode',
                          style: text.titleMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SlideTransition(
                  position: _buttonsSlide,
                  child: FadeTransition(
                    opacity: _buttonsFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppButton(
                          label: 'Kreiraj novi wallet',
                          icon: Icons.shield_outlined,
                          useSecondaryAccent: true,
                          onPressed: () => context.go(AppRoutes.onboardingCreate),
                        ),
                        const SizedBox(height: 12),
                        AppButton(
                          label: 'Uvezi postojeći wallet',
                          icon: Icons.download_outlined,
                          secondary: true,
                          useSecondaryAccent: true,
                          onPressed: () => context.go(AppRoutes.onboardingImport),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _buttonsFade,
                  child: Column(
                    children: [
                      Text(
                        'Privatni ključevi nikad ne napuštaju vaš uređaj',
                        style: text.labelMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.7)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(_version.isEmpty ? '' : _version, style: text.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
