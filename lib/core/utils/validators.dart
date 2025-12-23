import 'package:flutter/foundation.dart';

/// Validation helpers for addresses, amounts, and common wallet inputs
class Validators {
  /// Basic Solana address validation: base58 string length 32-44 characters
  static bool isValidSolanaAddress(String? input) {
    if (input == null || input.isEmpty) return false;
    final s = input.trim();
    final base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    final ok = s.length >= 32 && s.length <= 44 && base58.hasMatch(s);
    if (!ok) debugPrint('Invalid Solana address: $s');
    return ok;
    // Note: Full ed25519 pubkey validation requires decoding + checksum; add later.
  }

  /// Amount must be positive number. Allows up to 9 decimals (lamports precision)
  static bool isValidAmount(String? input) {
    if (input == null || input.isEmpty) return false;
    final s = input.replaceAll(',', '.');
    final re = RegExp(r'^(?!0{2,})(?:0|[1-9]\d*)(?:\.\d{1,9})?$');
    final ok = re.hasMatch(s) && double.tryParse(s) != null && double.parse(s) > 0;
    if (!ok) debugPrint('Invalid amount: $input');
    return ok;
  }

  /// Optional memo length cap to prevent abuse
  static bool isValidMemo(String? memo, {int maxLength = 120}) => memo == null || memo.length <= maxLength;
}
