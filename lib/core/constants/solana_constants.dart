/// Solana RPC endpoints and program IDs used by DOMOVINA Wallet
/// These are placeholders and can be expanded to support multiple clusters.
class SolanaConstants {
  // RPC endpoints
  static const String mainnetRpc = 'https://api.mainnet-beta.solana.com';
  static const String devnetRpc = 'https://api.devnet.solana.com';
  static const String testnetRpc = 'https://api.testnet.solana.com';

  // WebSocket endpoints (optional)
  static const String mainnetWs = 'wss://api.mainnet-beta.solana.com';
  static const String devnetWs = 'wss://api.devnet.solana.com';
  static const String testnetWs = 'wss://api.testnet.solana.com';

  // Common program IDs
  static const String systemProgram = '11111111111111111111111111111111';
  static const String tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const String associatedTokenProgram = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
  static const String memoProgram = 'Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo';
}
