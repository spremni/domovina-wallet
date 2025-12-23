import 'package:flutter/foundation.dart';
import 'package:domovina_wallet/core/constants/solana_constants.dart';

/// Abstraction for Solana RPC interactions
abstract class BlockchainService {
  Future<double> getSolBalance(String publicKey);
  Future<String> sendSol({required String from, required String to, required double amountSol, String? memo});
}

/// Basic placeholder implementation. Replace with real RPC client when integrating.
class BlockchainServiceImpl implements BlockchainService {
  final String rpcEndpoint;
  BlockchainServiceImpl({this.rpcEndpoint = SolanaConstants.mainnetRpc});

  @override
  Future<double> getSolBalance(String publicKey) async {
    debugPrint('Fetching SOL balance for $publicKey via $rpcEndpoint');
    // TODO: Integrate with a Solana client library or HTTP RPC
    return 0;
  }

  @override
  Future<String> sendSol({required String from, required String to, required double amountSol, String? memo}) async {
    debugPrint('Sending $amountSol SOL from $from to $to (memo: $memo) via $rpcEndpoint');
    // TODO: Build, sign and submit transaction via RPC
    return 'placeholder-signature';
  }
}
