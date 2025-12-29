import 'package:domovina_wallet/features/history/screens/history_screen.dart';
import 'package:domovina_wallet/features/pay/pay_screen.dart';
import 'package:domovina_wallet/features/receive/receive_screen.dart';
import 'package:domovina_wallet/features/send/send_screen.dart';
import 'package:domovina_wallet/features/send/screens/transaction_result_screen.dart';
import 'package:domovina_wallet/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:domovina_wallet/pages/splash_page.dart';
import 'package:domovina_wallet/features/onboarding/screens/onboarding_screen.dart';
import 'package:domovina_wallet/features/onboarding/screens/wallet_creation_screen.dart';
import 'package:domovina_wallet/features/onboarding/screens/wallet_import_screen.dart';
import 'package:domovina_wallet/features/onboarding/screens/biometric_setup_screen.dart';
import 'package:domovina_wallet/features/wallet/screens/wallet_home_screen.dart';
import 'package:domovina_wallet/features/wallet/screens/qr_scanner_screen.dart';
import 'package:domovina_wallet/features/wallet/screens/token_detail_screen.dart';
import 'package:domovina_wallet/features/wallet/screens/add_token_screen.dart';

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
        pageBuilder: (context, state) => const NoTransitionPage(child: WalletHomeScreen()),
      ),
      // Onboarding routes
      // Main feature routes (stubs for now)
      GoRoute(
        path: AppRoutes.send,
        name: 'send',
        pageBuilder: (context, state) {
          final args = state.extra is SendScreenArgs ? state.extra as SendScreenArgs : null;
          return NoTransitionPage(child: SendScreen(args: args));
        },
      ),
      GoRoute(
        path: AppRoutes.txResult,
        name: 'tx_result',
        pageBuilder: (context, state) {
          final args = state.extra is TransactionResultArgs ? state.extra as TransactionResultArgs : null;
          return NoTransitionPage(child: TransactionResultScreen(args: args));
        },
      ),
      GoRoute(
        path: AppRoutes.receive,
        name: 'receive',
        pageBuilder: (context, state) => const NoTransitionPage(child: ReceiveScreen()),
      ),
      GoRoute(
        path: AppRoutes.pay,
        name: 'pay',
        pageBuilder: (context, state) => const NoTransitionPage(child: PayScreen()),
      ),
      GoRoute(
        path: AppRoutes.scan,
        name: 'scan',
        pageBuilder: (context, state) => const NoTransitionPage(child: QrScannerScreen()),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.history,
        name: 'history',
        pageBuilder: (context, state) => const NoTransitionPage(child: HistoryScreen()),
      ),
      GoRoute(
        path: AppRoutes.tokenDetail,
        name: 'token_detail',
        pageBuilder: (context, state) {
          final args = state.extra is TokenDetailArgs ? state.extra as TokenDetailArgs : null;
          return NoTransitionPage(child: TokenDetailScreen(args: args));
        },
      ),
      GoRoute(
        path: AppRoutes.addToken,
        name: 'add_token',
        pageBuilder: (context, state) => const NoTransitionPage(child: AddTokenScreen()),
      ),
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
      GoRoute(
        path: AppRoutes.onboardingBiometrics,
        name: 'onboarding_biometrics',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: BiometricSetupScreen(),
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
  static const String onboardingBiometrics = '/onboarding/biometrics';
  static const String send = '/send';
  static const String receive = '/receive';
  static const String pay = '/pay';
  static const String scan = '/scan';
  static const String settings = '/settings';
  static const String history = '/history';
  static const String tokenDetail = '/token';
  static const String addToken = '/add-token';
  static const String txResult = '/tx-result';
}
