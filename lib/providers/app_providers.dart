import 'package:flutter/foundation.dart';

/// Global app state placeholder. Extend with proper state management as needed.
class WalletProvider extends ChangeNotifier {
  String? _activePublicKey;

  String? get activePublicKey => _activePublicKey;

  void setActivePublicKey(String? pubkey) {
    _activePublicKey = pubkey;
    notifyListeners();
  }
}
