import 'package:flutter/foundation.dart';

/// Simplified transaction model for display/history
@immutable
class TransactionModel {
  final String signature; // tx signature
  final String from;
  final String to;
  final double amountSol; // ui SOL amount (negative for outgoing)
  final DateTime timestamp;
  final String? memo;

  const TransactionModel({
    required this.signature,
    required this.from,
    required this.to,
    required this.amountSol,
    required this.timestamp,
    this.memo,
  });

  bool get isOutgoing => amountSol < 0;

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'from': from,
        'to': to,
        'amountSol': amountSol,
        'timestamp': timestamp.toIso8601String(),
        'memo': memo,
      };

  factory TransactionModel.fromJson(Map<String, dynamic> json) => TransactionModel(
        signature: json['signature'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
        amountSol: (json['amountSol'] as num).toDouble(),
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        memo: json['memo'] as String?,
      );
}
