import 'package:domovina_wallet/main.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:domovina_wallet/pages/splash_page.dart';
import 'package:domovina_wallet/features/onboarding/screens/onboarding_screen.dart';
import 'package:domovina_wallet/features/onboarding/screens/wallet_creation_screen.dart';
import 'package:domovina_wallet/features/onboarding/screens/wallet_import_screen.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        pageBuilder: (context, state) => const NoTransitionPage(child: SplashPage()),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MyHomePage(title: 'DOMOVINA Wallet'),
        ),
      ),
      // Onboarding routes
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboardingCreate,
        name: 'onboarding_create',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WalletCreationScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboardingImport,
        name: 'onboarding_import',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: WalletImportScreen(),
        ),
      ),
    ],
  );
}

/// Route path constants
/// Use these instead of hard-coding route strings
class AppRoutes {
  static const String splash = '/splash';
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String onboardingCreate = '/onboarding/create';
  static const String onboardingImport = '/onboarding/import';
}
