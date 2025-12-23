import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Simple key-value storage wrapper for local persistence
class StorageService {
  static const String _walletKey = 'active_wallet';

  Future<void> saveActiveWallet(Map<String, dynamic> wallet) async {
    // TODO: Replace with secure local storage or platform keystore.
    // Intentionally no-op to avoid adding dependencies at this stage.
    debugPrint('saveActiveWallet called with: ${jsonEncode(wallet)}');
  }

  Future<Map<String, dynamic>?> loadActiveWallet() async {
    // TODO: Replace with secure local storage or platform keystore.
    debugPrint('loadActiveWallet called');
    return null;
  }
}
