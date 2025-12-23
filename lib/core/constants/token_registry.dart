/// Token registry for supported SPL tokens in DOMOVINA Wallet.
///
/// This file defines chain-agnostic metadata for tokens we support. It is
/// intentionally UI-free (no Flutter imports). UI layers can translate
/// [TokenInfo.iconKey] into actual icons or assets.
library token_registry;

/// Static metadata for a token supported by the wallet.
class TokenInfo {
  /// SPL mint address. `null` for native SOL.
  final String? mint;

  /// Short ticker symbol (e.g., SOL, USDC, EURC).
  final String symbol;

  /// Number of decimals used to display UI amounts.
  final int decimals;

  /// Whether this represents native SOL (lamports).
  final bool isNative;

  /// Semantic icon key that the UI layer can map to an IconData or asset.
  /// Examples: 'solana', 'euro', 'dollar', 'hr_checkerboard'.
  final String iconKey;

  const TokenInfo({required this.mint, required this.symbol, required this.decimals, required this.isNative, required this.iconKey});

  /// Convenience for JSON or logging.
  Map<String, dynamic> toMap() => {
        'mint': mint,
        'symbol': symbol,
        'decimals': decimals,
        'isNative': isNative,
        'iconKey': iconKey,
      };
}

/// Registry of supported tokens with fast lookup by symbol or mint.
class TokenRegistry {
  TokenRegistry._();

  /// Wrapped SOL mint (So1111...) commonly used on Solana.
  static const String wSolMint = 'So11111111111111111111111111111111111111112';

  /// EURC mint on Solana mainnet.
  static const String eurcMint = 'HzwqbKZw8HxMN6bF2yFZNrht3c2iXXzpKcFu7uBEDKtr';

  /// USDC mint on Solana mainnet.
  static const String usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

  /// Placeholder MODRIC mint. Replace with a real mint when available.
  static const String modricMint = '<PLACEHOLDER_MINT>';

  /// Canonical list of supported tokens.
  static const List<TokenInfo> _tokens = [
    TokenInfo(
      mint: null,
      symbol: 'SOL',
      decimals: 9,
      isNative: true,
      iconKey: 'solana', // UI can map to Solana logo asset
    ),
    TokenInfo(
      mint: eurcMint,
      symbol: 'EURC',
      decimals: 6,
      isNative: false,
      iconKey: 'euro', // UI can map to a € symbol icon
    ),
    TokenInfo(
      mint: usdcMint,
      symbol: 'USDC',
      decimals: 6,
      isNative: false,
      iconKey: 'dollar', // UI can map to a $ symbol icon
    ),
    TokenInfo(
      mint: modricMint,
      symbol: 'MODRIC',
      decimals: 9,
      isNative: false,
      iconKey: 'hr_checkerboard', // UI can map to Croatian checkerboard
    ),
  ];

  /// Lookup maps (symbol and mint).
  static final Map<String, TokenInfo> _bySymbol = {
    for (final t in _tokens) t.symbol.toUpperCase(): t,
  };

  static final Map<String, TokenInfo> _byMint = {
    // Only include those with a non-null mint
    for (final t in _tokens)
      if (t.mint != null) (t.mint!.toLowerCase()): t,
  };

  /// Returns all supported tokens in canonical order.
  static List<TokenInfo> all() => List.unmodifiable(_tokens);

  /// Find token by its uppercase/lowercase symbol (case-insensitive). Returns null if not found.
  static TokenInfo? bySymbol(String symbol) => _bySymbol[symbol.trim().toUpperCase()];

  /// Find token by its SPL mint address (case-insensitive). Returns null if not found.
  ///
  /// Special handling: if the mint equals [wSolMint], we return native SOL.
  static TokenInfo? byMint(String mint) {
    final m = mint.trim().toLowerCase();
    if (m == wSolMint.toLowerCase()) return nativeSol;
    return _byMint[m];
  }

  /// True if the given symbol is supported.
  static bool isSupportedSymbol(String symbol) => bySymbol(symbol) != null;

  /// True if the given mint is supported. Accepts wrapped SOL as SOL.
  static bool isSupportedMint(String mint) => byMint(mint) != null;

  /// Returns the native SOL token metadata.
  static TokenInfo get nativeSol => _tokens.firstWhere((t) => t.isNative);

  /// Returns decimals for a symbol; null if unknown.
  static int? decimalsForSymbol(String symbol) => bySymbol(symbol)?.decimals;

  /// Returns decimals for a mint; null if unknown.
  static int? decimalsForMint(String mint) => byMint(mint)?.decimals;
}
