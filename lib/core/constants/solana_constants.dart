/// Solana configuration constants for DOMOVINA Wallet.
///
/// This class centralizes RPC endpoints, program IDs, and network settings
/// for multiple clusters. Values are static so the class is not meant to be
/// instantiated. Use the provided getters to resolve the active endpoints
/// based on the current cluster flag (defaults to devnet for development).
final class SolanaConstants {
  const SolanaConstants._();

  // ---------------------------------------------------------------------------
  // Cluster selection
  // ---------------------------------------------------------------------------
  /// Supported Solana clusters for this app.
  static const List<SolanaCluster> supportedClusters = [
    SolanaCluster.mainnet,
    SolanaCluster.devnet,
  ];

  /// Compile-time environment flag for selecting cluster.
  ///
  /// Set with: --dart-define=SOLANA_CLUSTER=mainnet|devnet
  /// Defaults to 'devnet' when not provided.
  static const String clusterFlag =
      String.fromEnvironment('SOLANA_CLUSTER', defaultValue: 'devnet');

  /// Returns the parsed cluster from [clusterFlag]. Defaults to devnet.
  static SolanaCluster get currentCluster =>
      clusterFlag.toLowerCase() == 'mainnet'
          ? SolanaCluster.mainnet
          : SolanaCluster.devnet;

  /// Convenience booleans for branch logic.
  static bool get isMainnet => currentCluster == SolanaCluster.mainnet;
  static bool get isDevnet => currentCluster == SolanaCluster.devnet;

  // ---------------------------------------------------------------------------
  // RPC & WebSocket endpoints
  // ---------------------------------------------------------------------------
  /// HTTP RPC endpoints per cluster.
  static const String mainnetRpc = 'https://api.mainnet-beta.solana.com';
  static const String devnetRpc = 'https://api.devnet.solana.com';

  /// Optional WebSocket endpoints per cluster.
  static const String mainnetWs = 'wss://api.mainnet-beta.solana.com';
  static const String devnetWs = 'wss://api.devnet.solana.com';

  /// Active HTTP RPC endpoint resolved from [currentCluster].
  static String get rpcEndpoint => isMainnet ? mainnetRpc : devnetRpc;

  /// Active WebSocket endpoint resolved from [currentCluster].
  static String get wsEndpoint => isMainnet ? mainnetWs : devnetWs;

  // ---------------------------------------------------------------------------
  // Program configuration
  // ---------------------------------------------------------------------------
  /// System Program ID (native SOL transfers, account creation, etc.).
  static const String systemProgram = '11111111111111111111111111111111';

  /// SPL Token Program ID (legacy SPL Token v1 program).
  static const String tokenProgram =
      'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';

  /// Associated Token Account (ATA) Program ID.
  static const String associatedTokenProgram =
      'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

  /// Memo Program ID (optional, human-readable notes on-chain).
  static const String memoProgram =
      'Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo';

  // ---------------------------------------------------------------------------
  // Network settings
  // ---------------------------------------------------------------------------
  /// Default commitment level used for reads and confirmations.
  /// Common options: 'processed' | 'confirmed' | 'finalized'.
  static const String defaultCommitment = 'confirmed';

  /// Client-side timeout for transaction confirmation.
  static const Duration transactionTimeout = Duration(seconds: 30);

  /// Maximum number of retries for transient RPC operations.
  static const int maxRetries = 3;
}

/// Enumeration of supported Solana clusters.
enum SolanaCluster { mainnet, devnet }
