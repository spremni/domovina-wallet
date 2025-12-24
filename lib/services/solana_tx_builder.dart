import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart' show base58decode;

/// Minimal legacy (v0) Solana transaction builder for native SOL transfers.
///
/// This implements just enough of the wire format to craft a simple System
/// Program transfer instruction (no nonce accounts, no address tables).
///
/// Wire format reference:
/// - Transaction = signatures (shortvec len + N*64 bytes) + Message
/// - Message = Header(3) + accountKeys(shortvec + 32*N) + recentBlockhash(32) + instructions(shortvec + ...)
/// - SystemProgram::Transfer instruction data = u32(2, LE) + u64(lamports, LE)
class SolanaTxBuilder {
  const SolanaTxBuilder._();

  /// Build and sign a legacy System Program transfer transaction.
  ///
  /// Parameters:
  /// - [fromPublicKeyBase58]: sender's public key (base58, 32 bytes)
  /// - [fromSecretKey64]: sender's secret key (64 bytes: private(32)+public(32))
  /// - [toPublicKeyBase58]: recipient's public key (base58, 32 bytes)
  /// - [lamports]: amount to transfer in lamports (u64)
  /// - [recentBlockhashBase58]: recent blockhash (base58, 32 bytes)
  ///
  /// Returns base64-encoded full transaction bytes ready for RPC sendTransaction.
  static Future<String> buildAndSignSystemTransfer({
    required String fromPublicKeyBase58,
    required Uint8List fromSecretKey64,
    required String toPublicKeyBase58,
    required BigInt lamports,
    required String recentBlockhashBase58,
    required Future<Uint8List> Function(Uint8List message, Uint8List secretKey) signer,
  }) async {
    // Decode inputs
    final fromPk = Uint8List.fromList(base58decode(fromPublicKeyBase58));
    final toPk = Uint8List.fromList(base58decode(toPublicKeyBase58));
    final recentBlockhash = Uint8List.fromList(base58decode(recentBlockhashBase58));

    if (fromPk.length != 32 || toPk.length != 32 || recentBlockhash.length != 32) {
      throw ArgumentError('Invalid key or blockhash length');
    }
    if (fromSecretKey64.length < 32) {
      throw ArgumentError('fromSecretKey64 must be at least 32 bytes');
    }

    // Accounts: [from (signer, writable), to (writable), systemProgram (readonly)]
    final systemProgramPk = Uint8List.fromList(base58decode('11111111111111111111111111111111'));

    // Build Message
    final message = BytesBuilder();

    // Header
    const numRequiredSignatures = 1; // from
    const numReadonlySigned = 0;
    const numReadonlyUnsigned = 1; // system program
    message.add([numRequiredSignatures, numReadonlySigned, numReadonlyUnsigned]);

    // Account keys
    final accountKeys = <Uint8List>[fromPk, toPk, systemProgramPk];
    message.add(_encodeShortVec(accountKeys.length));
    for (final k in accountKeys) {
      message.add(k);
    }

    // Recent blockhash
    message.add(recentBlockhash);

    // Instructions (1)
    message.add(_encodeShortVec(1));
    // Instruction 0: SystemProgram::Transfer
    const programIdIndex = 2; // system program index in accountKeys
    final accountIndices = [0, 1]; // from, to
    final data = _buildSystemTransferData(lamports);
    message.add([programIdIndex]);
    message.add(_encodeShortVec(accountIndices.length));
    message.add(accountIndices);
    message.add(_encodeShortVec(data.length));
    message.add(data);

    final messageBytes = message.toBytes();

    // Sign message
    final signature = await signer(messageBytes, fromSecretKey64);
    if (signature.length != 64) {
      debugPrint('Unexpected signature length: ${signature.length}');
    }

    // Transaction = signatures vec + message
    final tx = BytesBuilder();
    tx.add(_encodeShortVec(1));
    tx.add(signature);
    tx.add(messageBytes);

    final txBytes = tx.toBytes();
    return base64Encode(txBytes);
  }

  // --------------------------- Helpers ---------------------------

  static List<int> _buildSystemTransferData(BigInt lamports) {
    final b = BytesBuilder();
    // u32 discriminator = 2 (Transfer)
    b.add(_u32le(2));
    // u64 lamports LE
    b.add(_u64le(lamports));
    return b.toBytes();
  }

  static List<int> _u32le(int v) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, v, Endian.little);

  static List<int> _u64le(BigInt v) {
    var x = v;
    final out = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static List<int> _encodeShortVec(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        out.add(byte);
        break;
      } else {
        out.add(byte | 0x80);
      }
    }
    return out;
  }
}
