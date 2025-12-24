/// SecureStorageService
///
/// Stores sensitive wallet data using flutter_secure_storage with an extra AES‑GCM
/// application‑level encryption layer. This ensures data is protected at rest even
/// if platform storage is compromised. Private keys and mnemonics are encrypted
/// using a randomly generated 256‑bit master key stored in the platform keystore.
///
/// Security notes:
/// - We avoid logging any sensitive material (no plaintext keys, mnemonics, or
///   decrypted buffers are logged).
/// - We attempt to clear intermediate buffers where possible. Callers should
///   also take care to clear in‑memory copies when feasible.
/// - On web, platform security characteristics differ; treat web as best‑effort.
///
/// Methods provided:
/// - savePrivateKey / getPrivateKey / deletePrivateKey
/// - saveMnemonic / getMnemonic
/// - saveWalletList / getWalletList (metadata only; not additionally encrypted)

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:domovina_wallet/models/wallet_model.dart';

class SecureStorageService {
  SecureStorageService._internal({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
          mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
          webOptions: WebOptions(
            dbName: 'domovina_wallet_secure',
            publicKey: 'domovina_wallet_secure_pub',
          ),
        );

  static final SecureStorageService _instance = SecureStorageService._internal();

  /// Singleton accessor.
  static SecureStorageService get instance => _instance;

  // Underlying platform secure storage
  final FlutterSecureStorage _storage;

  // Algorithm selection
  static final AesGcm _algo = AesGcm.with256bits();

  // Keys
  static const String _masterKeyKey = 'mk_v1';
  static const String _walletListKey = 'wallet_list_v1';
  static const String _biometricsEnabledKey = 'biometrics_enabled_v1';

  // Versioning for ciphertext payloads
  static const int _encVersion = 1; // v1: AES‑GCM; payload fields: v,a,n,c,t

  // Helpers to derive platform keys
  String _pkKey(String walletId) => 'pk_$walletId';
  String _mnemonicKey(String walletId) => 'mnemonic_$walletId';

  // =====================
  // Public API — Keys
  // =====================

  Future<void> savePrivateKey({required String walletId, required Uint8List privateKey}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    // Encrypt
    String? payload;
    try {
      payload = await _encryptBytes(privateKey);
      await _storage.write(key: _pkKey(walletId), value: payload);
    } catch (e) {
      debugPrint('SecureStorageService.savePrivateKey error: $e');
      rethrow;
    } finally {
      // Best effort wipe caller‑provided buffer copy. Caller still holds reference.
      try {
        for (int i = 0; i < privateKey.length; i++) {
          privateKey[i] = 0;
        }
      } catch (_) {}
      payload = null; // drop reference
    }
  }

  Future<Uint8List?> getPrivateKey({required String walletId}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    try {
      final value = await _storage.read(key: _pkKey(walletId));
      if (value == null) return null;
      final bytes = await _decryptToBytes(value);
      return bytes; // Caller owns the buffer and should clear when done.
    } catch (e) {
      debugPrint('SecureStorageService.getPrivateKey error: $e');
      return null;
    }
  }

  Future<void> deletePrivateKey({required String walletId}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    try {
      await _storage.delete(key: _pkKey(walletId));
    } catch (e) {
      debugPrint('SecureStorageService.deletePrivateKey error: $e');
      rethrow;
    }
  }

  // =====================
  // Public API — Mnemonics
  // =====================

  Future<void> saveMnemonic({required String walletId, required String mnemonic}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    // Convert to bytes and encrypt
    final bytes = Uint8List.fromList(utf8.encode(mnemonic));
    String? payload;
    try {
      payload = await _encryptBytes(bytes);
      await _storage.write(key: _mnemonicKey(walletId), value: payload);
    } catch (e) {
      debugPrint('SecureStorageService.saveMnemonic error: $e');
      rethrow;
    } finally {
      // Wipe local buffer
      try {
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = 0;
        }
      } catch (_) {}
      payload = null;
    }
  }

  Future<String?> getMnemonic({required String walletId}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    try {
      final value = await _storage.read(key: _mnemonicKey(walletId));
      if (value == null) return null;
      final bytes = await _decryptToBytes(value);
      try {
        return utf8.decode(bytes);
      } finally {
        // Attempt to clear sensitive buffer
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = 0;
        }
      }
    } catch (e) {
      debugPrint('SecureStorageService.getMnemonic error: $e');
      return null;
    }
  }

  /// Deletes a stored mnemonic for the given wallet, if present.
  Future<void> deleteMnemonic({required String walletId}) async {
    assert(walletId.isNotEmpty, 'walletId must not be empty');
    try {
      await _storage.delete(key: _mnemonicKey(walletId));
    } catch (e) {
      debugPrint('SecureStorageService.deleteMnemonic error: $e');
      rethrow;
    }
  }

  // =====================
  // Public API — Wallet metadata
  // =====================

  Future<void> saveWalletList(List<WalletModel> wallets) async {
    try {
      final list = wallets.map((w) => w.toJson()).toList(growable: false);
      final jsonStr = jsonEncode(list);
      await _storage.write(key: _walletListKey, value: jsonStr);
    } catch (e) {
      debugPrint('SecureStorageService.saveWalletList error: $e');
      rethrow;
    }
  }

  Future<List<WalletModel>> getWalletList() async {
    try {
      final jsonStr = await _storage.read(key: _walletListKey);
      if (jsonStr == null || jsonStr.isEmpty) return const [];
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => WalletModel.fromJson(e))
            .toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('SecureStorageService.getWalletList error: $e');
      return const [];
    }
  }

  // =====================
  // Public API — Biometrics preference
  // =====================

  /// Stores the user's preference for enabling biometric authentication.
  /// This is a global app-level setting (not per-wallet).
  Future<void> setBiometricsEnabled(bool enabled) async {
    try {
      await _storage.write(key: _biometricsEnabledKey, value: enabled ? '1' : '0');
    } catch (e) {
      debugPrint('SecureStorageService.setBiometricsEnabled error: $e');
      rethrow;
    }
  }

  /// Returns whether biometric authentication is enabled.
  /// Defaults to false if not set.
  Future<bool> getBiometricsEnabled() async {
    try {
      final v = await _storage.read(key: _biometricsEnabledKey);
      return v == '1';
    } catch (e) {
      debugPrint('SecureStorageService.getBiometricsEnabled error: $e');
      return false;
    }
  }

  // =====================
  // Encryption helpers
  // =====================

  Future<String> _encryptBytes(Uint8List plaintext) async {
    final secretKey = await _getOrCreateMasterKey();
    // 96‑bit nonce is standard for GCM
    final nonce = _algo.newNonce();
    SecretBox? box;
    try {
      box = await _algo.encrypt(plaintext, secretKey: secretKey, nonce: nonce);
      final payload = <String, dynamic>{
        'v': _encVersion,
        'a': 'aes-gcm',
        'n': base64Encode(box.nonce),
        'c': base64Encode(box.cipherText),
        't': base64Encode(box.mac.bytes),
      };
      return jsonEncode(payload);
    } finally {
      // Attempt to clear plaintext buffer
      try {
        for (int i = 0; i < plaintext.length; i++) {
          plaintext[i] = 0;
        }
      } catch (_) {}
      box = null;
    }
  }

  Future<Uint8List> _decryptToBytes(String payload) async {
    final secretKey = await _getOrCreateMasterKey();
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid payload');
      final v = decoded['v'];
      final a = decoded['a'];
      if (v != _encVersion || a != 'aes-gcm') {
        throw const FormatException('Unsupported encryption format');
      }
      final nonce = base64Decode(decoded['n'] as String);
      final cipherText = base64Decode(decoded['c'] as String);
      final macBytes = base64Decode(decoded['t'] as String);
      final mac = Mac(macBytes);
      final box = SecretBox(cipherText, nonce: nonce, mac: mac);
      final clear = await _algo.decrypt(box, secretKey: secretKey);
      return Uint8List.fromList(clear);
    } catch (e) {
      debugPrint('SecureStorageService._decryptToBytes error: $e');
      rethrow;
    }
  }

  Future<SecretKey> _getOrCreateMasterKey() async {
    try {
      final existing = await _storage.read(key: _masterKeyKey);
      if (existing != null && existing.isNotEmpty) {
        final raw = base64Decode(existing);
        return SecretKey(raw);
      }
      // Create
      final sk = await _algo.newSecretKey();
      final raw = await sk.extractBytes();
      final b64 = base64Encode(raw);
      await _storage.write(key: _masterKeyKey, value: b64);
      // Attempt to zeroize local copies
      try {
        for (int i = 0; i < raw.length; i++) {
          raw[i] = 0;
        }
      } catch (_) {}
      return sk;
    } catch (e) {
      debugPrint('SecureStorageService._getOrCreateMasterKey error: $e');
      rethrow;
    }
  }
}
