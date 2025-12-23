import 'package:flutter/foundation.dart';

/// Represents a user's wallet metadata (public only; no seed/private storage here)
@immutable
class WalletModel {
  final String publicKey; // base58
  final String? name;
  final DateTime createdAt;

  const WalletModel({required this.publicKey, this.name, required this.createdAt});

  WalletModel copyWith({String? publicKey, String? name, DateTime? createdAt}) => WalletModel(
        publicKey: publicKey ?? this.publicKey,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        publicKey: json['publicKey'] as String,
        name: json['name'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
