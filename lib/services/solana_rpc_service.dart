import 'dart:async';
import 'dart:convert';

import 'package:domovina_wallet/core/constants/solana_constants.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/transaction_model.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lightweight Solana JSON-RPC client with retry logic and typed helpers.
///
/// Notes:
/// - Uses getLatestBlockhash under the hood for getRecentBlockhash() (modern API).
/// - Parses token accounts into [TokenBalance] using jsonParsed encoding.
/// - Parses transactions into [TransactionModel] using jsonParsed when available.
class SolanaRpcService {
  final Uri _endpoint;
  final http.Client _client;
  final Duration _timeout;
  final int _maxRetries;

  int _rpcId = 0;

  SolanaRpcService(
    String endpoint, {
    http.Client? client,
    Duration? timeout,
    int? maxRetries,
  })  : _endpoint = Uri.parse(endpoint),
        _client = client ?? http.Client(),
        _timeout = timeout ?? SolanaConstants.transactionTimeout,
        _maxRetries = maxRetries ?? SolanaConstants.maxRetries;

  /// Build a service targeting the active cluster from [SolanaConstants].
  factory SolanaRpcService.forCurrentCluster({http.Client? client}) =>
      SolanaRpcService(
        SolanaConstants.rpcEndpoint,
        client: client,
      );

  /// Get native SOL balance (lamports) for [address].
  Future<BigInt> getBalance(String address) async {
    final res = await _rpcCall<int>(
      method: 'getBalance',
      params: [
        address,
        {
          'commitment': SolanaConstants.defaultCommitment,
        },
      ],
      transform: (json) {
        final map = (json as Map?)?.cast<String, dynamic>() ?? const {};
        return (map['value'] as num?)?.toInt() ?? 0;
      },
    );
    return BigInt.from(res);
  }

  /// Get all SPL token accounts for an owner. Returns parsed [TokenBalance] list.
  Future<List<TokenBalance>> getTokenAccounts(String owner) async {
    final list = await _rpcCall<List<dynamic>>(
      method: 'getTokenAccountsByOwner',
      params: [
        owner,
        {
          'programId': SolanaConstants.tokenProgram,
        },
        {
          'encoding': 'jsonParsed',
          'commitment': SolanaConstants.defaultCommitment,
        },
      ],
      transform: (json) => (json['value'] as List?) ?? const [],
    );

    final balances = <TokenBalance>[];
    for (final item in list) {
      try {
        final map = (item as Map).cast<String, dynamic>();
        balances.add(TokenBalance.fromRpcParsedTokenAccount(map));
      } catch (e) {
        debugPrint('SolanaRpcService.getTokenAccounts: skip malformed item: $e');
      }
    }
    return balances;
  }

  /// Get a recent blockhash (latest) for building transactions.
  Future<String> getRecentBlockhash() async {
    final bh = await _rpcCall<String>(
      method: 'getLatestBlockhash',
      params: [
        {
          'commitment': SolanaConstants.defaultCommitment,
        }
      ],
      transform: (json) {
        final value = json['value'] as Map<String, dynamic>?;
        final blockhash = value?['blockhash']?.toString();
        if (blockhash == null || blockhash.isEmpty) {
          throw SolanaRpcException(
            method: 'getLatestBlockhash',
            code: -1,
            message: 'Empty blockhash in response',
          );
        }
        return blockhash;
      },
    );
    return bh;
  }

  /// Submit a base64-encoded signed transaction. Returns signature.
  Future<String> sendTransaction(String signedTxBase64) async {
    final sig = await _rpcCall<String>(
      method: 'sendTransaction',
      params: [
        signedTxBase64,
        {
          'encoding': 'base64',
          'skipPreflight': false,
          'maxRetries': _maxRetries,
        },
      ],
      transform: (json) => json.toString(),
    );
    return sig;
  }

  /// Get a transaction by signature. Returns [TransactionModel] or null if missing.
  Future<TransactionModel?> getTransaction(String signature, {String? ownerAddress}) async {
    final txJson = await _rpcCall<Map<String, dynamic>?>(
      method: 'getTransaction',
      params: [
        signature,
        {
          'commitment': SolanaConstants.defaultCommitment,
          'encoding': 'jsonParsed',
          // 'maxSupportedTransactionVersion': 0, // can be set if needed
        },
      ],
      transform: (json) => json, // result object or null
      allowNull: true,
    );
    if (txJson == null) return null;
    try {
      return TransactionModel.fromRpcGetTransaction(txJson, ownerAddress: ownerAddress);
    } catch (e) {
      debugPrint('SolanaRpcService.getTransaction parse error: $e');
      return null;
    }
  }

  /// Get recent transaction signatures for an address.
  Future<List<String>> getSignaturesForAddress(String address, {int limit = 20}) async {
    final list = await _rpcCall<List<dynamic>>(
      method: 'getSignaturesForAddress',
      params: [
        address,
        {
          'limit': limit,
        }
      ],
      transform: (json) => (json as List?) ?? const [],
    );
    return [
      for (final item in list)
        if (item is Map && item['signature'] != null) item['signature'].toString(),
    ];
  }

  /// Dispose the underlying HTTP client if you created this service.
  void close() => _client.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<T> _rpcCall<T>({
    required String method,
    required List<dynamic> params,
    required T Function(dynamic result) transform,
    bool allowNull = false,
  }) async {
    int attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final id = _rpcId++;
        final payload = jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        });

        final resp = await _client
            .post(
              _endpoint,
              headers: const {'content-type': 'application/json'},
              body: payload,
            )
            .timeout(_timeout);

        final bodyStr = utf8.decode(resp.bodyBytes);

        if (resp.statusCode >= 500 || resp.statusCode == 429) {
          throw SolanaRpcHttpException(
            statusCode: resp.statusCode,
            body: bodyStr,
            method: method,
          );
        }

        final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
        if (decoded['error'] != null) {
          final err = decoded['error'] as Map<String, dynamic>;
          final code = (err['code'] as num?)?.toInt() ?? -1;
          final message = (err['message'] ?? 'RPC error').toString();
          // Some RPCs return error object even when result is present; prefer error
          throw SolanaRpcException(method: method, code: code, message: message);
        }

        final result = decoded['result'];
        if (result == null) {
          if (allowNull) return transform(result);
          throw SolanaRpcException(method: method, code: -1, message: 'Null result');
        }
        return transform(result);
      } catch (e) {
        final isLast = attempt >= _maxRetries;
        if (!isLast && _shouldRetry(e)) {
          final delayMs = 250 * attempt * attempt; // quadratic backoff
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        debugPrint('RPC $method failed (attempt $attempt/$_maxRetries): $e');
        rethrow;
      }
    }
  }

  bool _shouldRetry(Object e) {
    if (e is TimeoutException) return true;
    if (e is SolanaRpcHttpException) {
      // Retry on 5xx and 429
      return e.statusCode >= 500 || e.statusCode == 429;
    }
    if (e is SolanaRpcException) {
      // Retry known transient RPC codes
      const transientCodes = {
        -32005, // blockstore rpc latency
        -32009, // node behind
        -32603, // internal error
      };
      return transientCodes.contains(e.code);
    }
    return false;
  }
}

/// Represents a structured JSON-RPC error returned by Solana.
class SolanaRpcException implements Exception {
  final String method;
  final int code;
  final String message;
  SolanaRpcException({required this.method, required this.code, required this.message});
  @override
  String toString() => 'SolanaRpcException(method: $method, code: $code, message: $message)';
}

/// HTTP-level failure while calling the RPC endpoint.
class SolanaRpcHttpException implements Exception {
  final int statusCode;
  final String body;
  final String method;
  SolanaRpcHttpException({required this.statusCode, required this.body, required this.method});
  @override
  String toString() => 'SolanaRpcHttpException(method: $method, status: $statusCode, body: $body)';
}
