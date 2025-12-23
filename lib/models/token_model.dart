import 'dart:math' as math;

import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';

/// Model representing a token balance (SPL token or native SOL).
class TokenBalance {
  /// SPL mint address. Null for native SOL.
  final String? mint;

  /// Short ticker (e.g., SOL, USDC, EURC).
  final String symbol;

  /// Human-friendly name (e.g., Solana, USD Coin, EURC). Can mirror [symbol] if unknown.
  final String name;

  /// Raw amount in the smallest unit (lamports for SOL, base units for SPL).
  final BigInt balance;

  /// Number of decimals used by this token (9 for SOL, 6 for USDC/EURC, etc.).
  final int decimals;

  /// Optional icon URL or asset reference (future-proof). UI decides how to render.
  final String? iconUrl;

  /// True if this is native SOL (i.e., [mint] is null or wrapped SOL mapped to SOL).
  final bool isNative;

  /// Optional per-unit price placeholders for future price integration.
  /// If provided, [usdValue]/[eurValue] will be computed from [uiAmount] * price.
  final double? priceUsd;
  final double? priceEur;

  const TokenBalance({required this.mint, required this.symbol, required this.name, required this.balance, required this.decimals, this.iconUrl, required this.isNative, this.priceUsd, this.priceEur});

  /// UI-friendly amount computed from [balance] and [decimals].
  double get uiAmount {
    if (balance == BigInt.zero) return 0;
    // Convert BigInt to double with decimal scaling. Precision is sufficient for UI display.
    final scale = math.pow(10, decimals).toDouble();
    return balance.toDouble() / scale;
  }

  /// Computed USD value = uiAmount * priceUsd (if available)
  double? get usdValue => priceUsd == null ? null : uiAmount * priceUsd!;

  /// Computed EUR value = uiAmount * priceEur (if available)
  double? get eurValue => priceEur == null ? null : uiAmount * priceEur!;

  /// A practical formatted balance string respecting decimal precision.
  /// Defaults to printing up to [decimals] (capped to 9) places with the symbol prefix.
  String formattedBalance({int? fractionDigits}) {
    final digits = (fractionDigits ?? decimals).clamp(0, 9);
    final fixed = uiAmount.toStringAsFixed(digits);
    return symbol.isEmpty ? fixed : '$symbol $fixed';
  }

  /// Generic JSON serialization for persistence (not RPC response shape).
  Map<String, dynamic> toJson() => {
        'mint': mint,
        'symbol': symbol,
        'name': name,
        'balance': balance.toString(),
        'decimals': decimals,
        'iconUrl': iconUrl,
        'isNative': isNative,
        'priceUsd': priceUsd,
        'priceEur': priceEur,
      };

  /// Create from JSON created by [toJson].
  factory TokenBalance.fromJson(Map<String, dynamic> json) => TokenBalance(
        mint: json['mint'] as String?,
        symbol: json['symbol'] as String,
        name: json['name'] as String? ?? (json['symbol'] as String),
        balance: BigInt.parse(json['balance'] as String),
        decimals: (json['decimals'] as num).toInt(),
        iconUrl: json['iconUrl'] as String?,
        isNative: (json['isNative'] as bool?) ?? false,
        priceUsd: (json['priceUsd'] as num?)?.toDouble(),
        priceEur: (json['priceEur'] as num?)?.toDouble(),
      );

  /// Copy with overrides.
  TokenBalance copyWith({String? mint, String? symbol, String? name, BigInt? balance, int? decimals, String? iconUrl, bool? isNative, double? priceUsd, double? priceEur}) => TokenBalance(
        mint: mint ?? this.mint,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        balance: balance ?? this.balance,
        decimals: decimals ?? this.decimals,
        iconUrl: iconUrl ?? this.iconUrl,
        isNative: isNative ?? this.isNative,
        priceUsd: priceUsd ?? this.priceUsd,
        priceEur: priceEur ?? this.priceEur,
      );

  @override
  String toString() => 'TokenBalance(symbol: $symbol, mint: ${mint ?? 'SOL'}, balance: $balance, decimals: $decimals, uiAmount: ${uiAmount.toStringAsFixed(6)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TokenBalance && other.mint == mint && other.symbol == symbol && other.decimals == decimals);

  @override
  int get hashCode => Object.hash(mint, symbol, decimals);

  // -------- Factories from common Solana RPC responses --------

  /// Build a native SOL balance from `getBalance` RPC result shape:
  /// { "value": <lamports:int> }
  factory TokenBalance.fromRpcGetBalance(Map<String, dynamic> json) {
    final lamports = BigInt.from((json['value'] as num?)?.toInt() ?? 0);
    final info = TokenRegistry.nativeSol;
    return TokenBalance(
      mint: null,
      symbol: info.symbol,
      name: 'Solana',
      balance: lamports,
      decimals: info.decimals,
      iconUrl: null,
      isNative: true,
    );
  }

  /// Build from a `getTokenAccountsByOwner` item with parsed data enabled.
  /// Expected shape: {
  ///   "account": { "data": { "parsed": { "info": { "mint": String, "tokenAmount": { "amount": String, "decimals": int, "uiAmount": num? }}}}}
  /// }
  factory TokenBalance.fromRpcParsedTokenAccount(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    final data = account?['data'] as Map<String, dynamic>?;
    final parsed = data?['parsed'] as Map<String, dynamic>?;
    final info = parsed?['info'] as Map<String, dynamic>?;
    final mintStr = (info?['mint'] as String?)?.trim();
    final tokenAmount = info?['tokenAmount'] as Map<String, dynamic>?;
    final amountStr = tokenAmount?['amount']?.toString() ?? '0';
    final dec = (tokenAmount?['decimals'] as num?)?.toInt() ?? TokenRegistry.byMint(mintStr ?? '')?.decimals ?? 0;

    final reg = mintStr == null ? TokenRegistry.nativeSol : TokenRegistry.byMint(mintStr) ?? TokenInfo(mint: mintStr, symbol: '', decimals: dec, isNative: false, iconKey: '');

    return TokenBalance(
      mint: mintStr,
      symbol: reg.symbol.isEmpty ? (mintStr == null ? 'SOL' : '') : reg.symbol,
      name: reg.symbol.isEmpty ? (mintStr == null ? 'Solana' : mintStr) : reg.symbol,
      balance: BigInt.tryParse(amountStr) ?? BigInt.zero,
      decimals: dec,
      iconUrl: null,
      isNative: reg.isNative,
    );
  }

  /// Convenience factory for native SOL from lamports amount.
  factory TokenBalance.nativeSolFromLamports(BigInt lamports) {
    final info = TokenRegistry.nativeSol;
    return TokenBalance(mint: null, symbol: info.symbol, name: 'Solana', balance: lamports, decimals: info.decimals, iconUrl: null, isNative: true);
  }
}
