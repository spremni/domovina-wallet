import 'package:flutter/foundation.dart';

/// Representation of an SPL token held by the wallet
@immutable
class TokenModel {
  final String mint; // token mint address
  final String symbol;
  final int decimals; // token decimals
  final double amount; // ui amount (decimals applied)

  const TokenModel({required this.mint, required this.symbol, required this.decimals, required this.amount});

  TokenModel copyWith({String? mint, String? symbol, int? decimals, double? amount}) => TokenModel(
        mint: mint ?? this.mint,
        symbol: symbol ?? this.symbol,
        decimals: decimals ?? this.decimals,
        amount: amount ?? this.amount,
      );

  Map<String, dynamic> toJson() => {
        'mint': mint,
        'symbol': symbol,
        'decimals': decimals,
        'amount': amount,
      };

  factory TokenModel.fromJson(Map<String, dynamic> json) => TokenModel(
        mint: json['mint'] as String,
        symbol: json['symbol'] as String? ?? '',
        decimals: (json['decimals'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}
