/// Minimal token registry for common SPL tokens by symbol.
/// Extend this list or migrate to a remote registry as needed.
class TokenRegistry {
  // Mapping of token symbol to mint address (mainnet)
  static const Map<String, String> mints = {
    'SOL': 'So11111111111111111111111111111111111111112',
    'USDC': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
    'USDT': 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
  };
}
