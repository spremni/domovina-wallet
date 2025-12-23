import 'package:flutter/foundation.dart';
import 'package:domovina_wallet/core/constants/token_registry.dart';

/// Transaction types displayed in history.
enum TransactionType { send, receive, swap, unknown }

/// Network confirmation status for a transaction.
enum TransactionStatus { pending, confirmed, failed }

/// Transaction model for display/history
@immutable
class TransactionModel {
  /// Transaction signature (hash)
  final String signature;

  /// Time the block was processed
  final DateTime timestamp;

  /// High-level classification of the transaction
  final TransactionType type;

  /// Network status
  final TransactionStatus status;

  /// Raw amount in smallest units (lamports for SOL, token units for SPL)
  final BigInt amount;

  /// Token metadata (native SOL or SPL token)
  final TokenInfo token;

  /// Source address
  final String fromAddress;

  /// Destination address
  final String toAddress;

  /// Fee paid in lamports
  final int fee;

  /// Optional memo
  final String? memo;

  const TransactionModel({
    required this.signature,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.amount,
    required this.token,
    required this.fromAddress,
    required this.toAddress,
    required this.fee,
    this.memo,
  });

  /// Outgoing relative to the model's classification.
  /// When created with [fromRpcGetTransaction] and an owner address,
  /// this will be true for sends, false for receives.
  bool get isOutgoing => type == TransactionType.send;

  /// Short human-friendly date (YYYY-MM-DD HH:mm)
  String get formattedDateTime {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'status': status.name,
        'amount': amount.toString(),
        'token': token.toMap(),
        'fromAddress': fromAddress,
        'toAddress': toAddress,
        'fee': fee,
        'memo': memo,
      };

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? 'unknown';
    final statusStr = (json['status'] as String?) ?? 'confirmed';
    return TransactionModel(
      signature: json['signature'] as String,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => TransactionType.unknown,
      ),
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => TransactionStatus.confirmed,
      ),
      amount: BigInt.parse((json['amount'] ?? '0').toString()),
      token: _tokenFromMap(json['token'] as Map<String, dynamic>?),
      fromAddress: json['fromAddress'] as String? ?? '',
      toAddress: json['toAddress'] as String? ?? '',
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      memo: json['memo'] as String?,
    );
  }

  /// Parse a transaction returned by Solana getTransaction (jsonParsed preferred).
  ///
  /// Provide [ownerAddress] (base58) to classify send vs receive. If omitted,
  /// type may be set to [TransactionType.unknown] when ambiguous.
  factory TransactionModel.fromRpcGetTransaction(
    Map<String, dynamic> tx, {
    String? ownerAddress,
  }) {
    try {
      // Signature
      String signature = '';
      final txObj = tx['transaction'] as Map<String, dynamic>?;
      final sigs = (txObj != null ? txObj['signatures'] : tx['signatures']) as List<dynamic>?;
      if (sigs != null && sigs.isNotEmpty) signature = sigs.first.toString();

      // Timestamp
      final blockTime = tx['blockTime'];
      final timestamp = blockTime is int ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000) : DateTime.now();

      // Meta
      final meta = tx['meta'] as Map<String, dynamic>?;
      final fee = (meta?['fee'] as num?)?.toInt() ?? 0;
      final err = meta?['err'];
      final status = err == null ? TransactionStatus.confirmed : TransactionStatus.failed;

      // Instructions (jsonParsed preferred)
      final message = txObj != null ? txObj['message'] as Map<String, dynamic>? : null;
      final List<dynamic> ixListRaw = (message?['instructions'] as List<dynamic>?) ?? const [];

      String from = '';
      String to = '';
      BigInt rawAmount = BigInt.zero;
      TokenInfo token = TokenRegistry.nativeSol;
      String? memo;
      bool isSwap = false;

      for (final ix in ixListRaw) {
        // jsonParsed instruction shape
        final ixMap = (ix as Map?)?.cast<String, dynamic>();
        if (ixMap == null) continue;

        final parsedRaw = ixMap['parsed'];
        final program = (ixMap['program'] ?? ixMap['programId'])?.toString();

        // SPL Memo program handling
        if (program == 'spl-memo' || program == 'memo') {
          // Some nodes place the memo as a string in parsed, others under info.memo
          if (parsedRaw is String) {
            memo = parsedRaw;
          } else if (parsedRaw is Map) {
            final map = parsedRaw.cast<String, dynamic>();
            memo = (map['info']?['memo'] as String?) ?? memo;
          }
          continue;
        }

        final parsed = parsedRaw is Map ? (parsedRaw as Map).cast<String, dynamic>() : null;
        if (parsed == null) {
          // Non-parsed instruction; skip
          continue;
        }

        final type = (parsed['type'] ?? '').toString();
        final info = (parsed['info'] as Map?)?.cast<String, dynamic>() ?? const {};

        // Heuristic: detect swaps by presence of both token send and receive instructions
        if (program == 'spl-token' && (type.contains('transfer'))) {
          // Token transfer or transferChecked
          final mint = (info['mint'] ?? (info['token']?['mint']))?.toString();
          final tokenAmountMap = (info['tokenAmount'] as Map?)?.cast<String, dynamic>();
          BigInt amt;
          int? decimals;
          if (tokenAmountMap != null && tokenAmountMap['amount'] != null) {
            amt = BigInt.parse(tokenAmountMap['amount'].toString());
            decimals = (tokenAmountMap['decimals'] as num?)?.toInt();
          } else if (info['amount'] != null) {
            // Some nodes provide amount as raw units string/number
            amt = BigInt.parse(info['amount'].toString());
            decimals = (info['decimals'] as num?)?.toInt();
          } else {
            // Fallback: try token balance deltas (hard to attribute per ix) — skip
            continue;
          }

          final src = info['source']?.toString() ?? info['authority']?.toString() ?? '';
          final dst = info['destination']?.toString() ?? '';

          // Prefer first transfer encountered as primary summary
          if (rawAmount == BigInt.zero) {
            rawAmount = amt;
            from = src;
            to = dst;
            final metaToken = mint != null ? (TokenRegistry.byMint(mint) ?? TokenRegistry.nativeSol) : TokenRegistry.nativeSol;
            token = metaToken;
          } else {
            // Another transfer in same tx => likely a swap
            isSwap = true;
          }
        } else if (program == 'system' && type == 'transfer') {
          // Native SOL transfer
          final lamports = (info['lamports'] as num?)?.toInt();
          final src = info['source']?.toString() ?? '';
          final dst = info['destination']?.toString() ?? '';
          if (lamports != null) {
            if (rawAmount == BigInt.zero) {
              rawAmount = BigInt.from(lamports);
              from = src;
              to = dst;
              token = TokenRegistry.nativeSol;
            } else {
              // Multiple system transfers = complex tx, mark swap-ish
              isSwap = true;
            }
          }
        }
      }

      // Fallbacks if we couldn't parse instructions
      if (from.isEmpty || to.isEmpty) {
        // Try to infer addresses from post/pre token balances (best-effort)
        final postTokenBalances = (meta?['postTokenBalances'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final preTokenBalances = (meta?['preTokenBalances'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        if (postTokenBalances.isNotEmpty && preTokenBalances.isNotEmpty) {
          // Look for entry that decreased (sender) and increased (receiver)
          String? mint;
          BigInt delta = BigInt.zero;
          for (final pre in preTokenBalances) {
            final owner = (pre['owner'] ?? '').toString();
            final m = (pre['mint'] ?? '').toString();
            final preAmtStr = pre['uiTokenAmount']?['amount']?.toString() ?? '0';
            final post = postTokenBalances.firstWhere(
              (p) => p['owner'] == owner && p['mint'] == m,
              orElse: () => const {},
            );
            final postAmtStr = post.isEmpty ? '0' : (post['uiTokenAmount']?['amount']?.toString() ?? '0');
            final preAmt = BigInt.tryParse(preAmtStr) ?? BigInt.zero;
            final postAmt = BigInt.tryParse(postAmtStr) ?? BigInt.zero;
            if (preAmt > postAmt) {
              from = owner;
              mint = m;
              delta = preAmt - postAmt;
            } else if (postAmt > preAmt) {
              to = owner;
            }
            if (delta > BigInt.zero && to.isNotEmpty) break;
          }
          if (delta > BigInt.zero) {
            rawAmount = rawAmount == BigInt.zero ? delta : rawAmount;
            if (mint != null && mint!.isNotEmpty) token = TokenRegistry.byMint(mint!) ?? token;
          }
        }
      }

      // Classification
      TransactionType txType = TransactionType.unknown;
      if (isSwap) {
        txType = TransactionType.swap;
      } else if (ownerAddress != null && ownerAddress.isNotEmpty) {
        if (from == ownerAddress) txType = TransactionType.send;
        if (to == ownerAddress) txType = txType == TransactionType.send ? TransactionType.unknown : TransactionType.receive;
      } else {
        // Without owner context, default transfers to 'send' for consistency
        if (from.isNotEmpty && to.isNotEmpty) txType = TransactionType.send;
      }

      return TransactionModel(
        signature: signature,
        timestamp: timestamp,
        type: txType,
        status: status,
        amount: rawAmount,
        token: token,
        fromAddress: from,
        toAddress: to,
        fee: fee,
        memo: memo,
      );
    } catch (e) {
      debugPrint('TransactionModel.fromRpcGetTransaction parse error: $e');
      return TransactionModel(
        signature: '',
        timestamp: DateTime.now(),
        type: TransactionType.unknown,
        status: TransactionStatus.failed,
        amount: BigInt.zero,
        token: TokenRegistry.nativeSol,
        fromAddress: '',
        toAddress: '',
        fee: 0,
        memo: null,
      );
    }
  }

  static TokenInfo _tokenFromMap(Map<String, dynamic>? map) {
    if (map == null) return TokenRegistry.nativeSol;
    final mint = map['mint'];
    final symbol = map['symbol'];
    final decimals = (map['decimals'] as num?)?.toInt();
    final isNative = map['isNative'] == true;
    final iconKey = map['iconKey']?.toString() ?? 'token';
    try {
      // Prefer registry if possible
      if (mint != null) {
        final reg = TokenRegistry.byMint(mint.toString());
        if (reg != null) return reg;
      }
      if (symbol != null) {
        final reg = TokenRegistry.bySymbol(symbol.toString());
        if (reg != null) return reg;
      }
      // Construct an ad-hoc TokenInfo as a fallback
      return TokenInfo(
        mint: mint?.toString(),
        symbol: symbol?.toString() ?? (isNative ? 'SOL' : 'TOKEN'),
        decimals: decimals ?? (isNative ? 9 : 0),
        isNative: isNative,
        iconKey: iconKey,
      );
    } catch (_) {
      return TokenRegistry.nativeSol;
    }
  }
}
