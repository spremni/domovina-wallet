/// Wallet model representing a user's public Solana wallet identity.
///
/// IMPORTANT: This model intentionally does NOT store private keys.
/// Private keys should be handled via secure storage and key management services.
class WalletModel {
  /// Unique identifier for this wallet (UUID string)
  final String id;

  /// User-defined wallet name for display purposes
  final String name;

  /// Base58-encoded public key
  final String publicKey;

  /// Creation timestamp
  final DateTime createdAt;

  /// Whether this wallet is the default/primary one
  final bool isDefault;

  const WalletModel({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.createdAt,
    this.isDefault = false,
  });

  /// Factory constructor to build from JSON map
  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        id: json['id'] as String,
        name: json['name'] as String,
        publicKey: json['publicKey'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isDefault: (json['isDefault'] as bool?) ?? false,
      );

  /// Serialize model to JSON map for persistence
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'publicKey': publicKey,
        'createdAt': createdAt.toIso8601String(),
        'isDefault': isDefault,
      };

  /// Abbreviated address in the form of first 4...last 4 characters.
  String get abbreviatedAddress {
    final pk = publicKey;
    if (pk.length <= 10) return pk; // Already short enough
    final start = pk.substring(0, 4);
    final end = pk.substring(pk.length - 4);
    return '$start...$end';
  }

  /// Creates a copy with modified fields.
  WalletModel copyWith({
    String? id,
    String? name,
    String? publicKey,
    DateTime? createdAt,
    bool? isDefault,
  }) =>
      WalletModel(
        id: id ?? this.id,
        name: name ?? this.name,
        publicKey: publicKey ?? this.publicKey,
        createdAt: createdAt ?? this.createdAt,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is WalletModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'WalletModel(id: $id, name: $name, publicKey: $publicKey, createdAt: ${createdAt.toIso8601String()}, isDefault: $isDefault)';
}
