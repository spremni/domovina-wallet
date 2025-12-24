import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:ed25519_hd_key/ed25519_hd_key.dart' as edhd;
import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart' show base58encode;
import 'package:cryptography/cryptography.dart' as crypto;

/// A minimal Ed25519 HD keypair representation tailored for Solana.
///
/// Holds the raw public key (32 bytes) and the concatenated secret key
/// (64 bytes = private seed 32 + public key 32). This mirrors common
/// Solana SDK expectations for signing.
class Ed25519HDKeyPair {
  final Uint8List publicKey; // 32 bytes
  final Uint8List secretKey; // 64 bytes: [private(32) + public(32)]

  const Ed25519HDKeyPair({required this.publicKey, required this.secretKey});

  /// Base58-encoded public key (Solana address)
  String get address => base58encode(publicKey);
}

/// CryptoService provides mnemonic generation/validation, seed derivation,
/// Solana Ed25519 HD key derivation on BIP44 path, address encoding, and signing.
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  /// Generate a 12-word BIP39 mnemonic using a CSPRNG.
  String generateMnemonic() {
    // 128 bits of entropy -> 12 words
    final mnemonic = bip39.generateMnemonic(strength: 128);
    return mnemonic.trim();
  }

  /// Validate mnemonic checksum and word list.
  bool validateMnemonic(String mnemonic) {
    final normalized = _normalizeMnemonic(mnemonic);
    try {
      return bip39.validateMnemonic(normalized);
    } catch (e) {
      debugPrint('validateMnemonic failed: $e');
      return false;
    }
  }

  /// Convert BIP39 mnemonic to a 64-byte seed using PBKDF2-HMAC-SHA512.
  Uint8List mnemonicToSeed(String mnemonic, {String passphrase = ''}) {
    final normalized = _normalizeMnemonic(mnemonic);
    try {
      // bip39 returns 64-byte seed
      final seed = bip39.mnemonicToSeed(normalized, passphrase: passphrase);
      return seed;
    } catch (e) {
      debugPrint('mnemonicToSeed failed: $e');
      rethrow;
    }
  }

  /// Derive Solana Ed25519 keypair from seed using BIP44 path:
  /// m/44'/501'/{accountIndex}'/0'
  ///
  /// The returned keypair contains:
  /// - publicKey (32 bytes)
  /// - secretKey (64 bytes): private(32) + public(32)
  Future<Ed25519HDKeyPair> deriveKeypair(Uint8List seed, {int accountIndex = 0}) async {
    assert(accountIndex >= 0, 'accountIndex must be >= 0');
    try {
      final path = "m/44'/501'/${accountIndex}'/0'";
      final keyData = await edhd.ED25519_HD_KEY.derivePath(path, seed);
      final privateKey32 = Uint8List.fromList(keyData.key); // 32 bytes

      // Compute public key from the 32-byte private seed using Ed25519.
      final algo = crypto.Ed25519();
      final keyPair = await algo.newKeyPairFromSeed(privateKey32);
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBytes = publicKey.bytes;

      // Compose 64-byte secret key (private + public) as commonly used by Solana.
      final secretKey64 = Uint8List(64)
        ..setRange(0, 32, privateKey32)
        ..setRange(32, 64, publicKeyBytes);

      return Ed25519HDKeyPair(publicKey: Uint8List.fromList(publicKeyBytes), secretKey: secretKey64);
    } catch (e) {
      debugPrint('deriveKeypair failed: $e');
      rethrow;
    }
  }

  /// Encode a public key to a base58 Solana address.
  String publicKeyToBase58(Uint8List publicKey) => base58encode(publicKey);

  /// Sign a transaction/message with Ed25519 using the provided 64-byte secretKey.
  /// Returns the 64-byte signature.
  Future<Uint8List> signTransaction(Uint8List message, Uint8List secretKey) async {
    try {
      if (secretKey.length < 32) {
        throw ArgumentError('secretKey must be at least 32 bytes');
      }
      final privateSeed32 = Uint8List.fromList(secretKey.sublist(0, 32));
      final algo = crypto.Ed25519();
      final keyPair = await algo.newKeyPairFromSeed(privateSeed32);
      final sig = await algo.sign(message, keyPair: keyPair);
      return Uint8List.fromList(sig.bytes);
    } catch (e) {
      debugPrint('signTransaction failed: $e');
      rethrow;
    }
  }

  String _normalizeMnemonic(String m) => m.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
