import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/services/crypto_service.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:domovina_wallet/services/solana_rpc_service.dart';
import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart' show base58decode;
import 'package:cryptography/cryptography.dart' as crypto;

/// WalletProvider manages wallets, balances, and token portfolios.
///
/// Responsibilities:
/// - Load and persist wallet metadata list
/// - Manage current wallet selection (isDefault)
/// - Fetch SOL balance and SPL token balances
/// - Create/import/delete wallets with secure key storage
/// - Expose simple error state with auto clear
class WalletProvider extends ChangeNotifier {
  final SecureStorageService _secure = SecureStorageService.instance;
  final CryptoService _crypto = CryptoService.instance;
  final SolanaRpcService _rpc = SolanaRpcService.forCurrentCluster();

  List<WalletModel> wallets = const [];
  WalletModel? currentWallet;
  BigInt solBalance = BigInt.zero; // Lamports
  List<TokenBalance> tokens = const []; // SPL tokens only (excludes native SOL)
  bool isLoading = false;
  String? error;

  Timer? _errorTimer;
  bool _disposed = false;

  // ---------------- Public API ----------------

  Future<void> loadWallets() async {
    _setLoading(true);
    try {
      final list = await _secure.getWalletList();
      wallets = List.unmodifiable(list);
      if (wallets.isEmpty) {
        currentWallet = null;
        solBalance = BigInt.zero;
        tokens = const [];
      } else {
        currentWallet = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
        // Refresh balances for the selected wallet
        await refreshBalances();
      }
      _notify();
    } catch (e) {
      debugPrint('WalletProvider.loadWallets error: $e');
      _setError('Neuspješno učitavanje walleta');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> selectWallet(String walletId) async {
    try {
      if (wallets.isEmpty) return;
      final idx = wallets.indexWhere((w) => w.id == walletId);
      if (idx < 0) {
        _setError('Wallet nije pronađen');
        return;
      }
      final selected = wallets[idx];
      currentWallet = selected;
      // Update isDefault flags and persist
      final updated = [
        for (final w in wallets) w.copyWith(isDefault: w.id == selected.id),
      ];
      wallets = List.unmodifiable(updated);
      await _secure.saveWalletList(updated);
      _notify();
      await refreshBalances();
    } catch (e) {
      debugPrint('WalletProvider.selectWallet error: $e');
      _setError('Neuspješan odabir walleta');
    }
  }

  Future<void> refreshBalances() async {
    final pubkey = currentWallet?.publicKey;
    if (pubkey == null || pubkey.isEmpty) {
      solBalance = BigInt.zero;
      tokens = const [];
      _notify();
      return;
    }
    _setLoading(true);
    try {
      final balanceF = _rpc.getBalance(pubkey);
      final tokensF = _rpc.getTokenAccounts(pubkey);
      final results = await Future.wait([balanceF, tokensF]);
      solBalance = results[0] as BigInt;
      final spl = (results[1] as List<TokenBalance>)
        ..removeWhere((t) => t.isNative)
        ..sort((a, b) => a.symbol.compareTo(b.symbol));
      tokens = List.unmodifiable(spl);
      _notify();
    } catch (e) {
      debugPrint('WalletProvider.refreshBalances error: $e');
      _setError('Neuspješno osvježavanje podataka');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createWallet(String name, String mnemonic) async {
    _setLoading(true);
    try {
      final normalized = mnemonic.trim();
      if (!_crypto.validateMnemonic(normalized)) {
        throw ArgumentError('Neispravna recovery phrase');
      }
      final seed = _crypto.mnemonicToSeed(normalized);
      final kp = await _crypto.deriveKeypair(seed, accountIndex: 0);
      final walletId = _newWalletId();
      await _secure.savePrivateKey(walletId: walletId, privateKey: Uint8List.fromList(kp.secretKey));
      await _secure.saveMnemonic(walletId: walletId, mnemonic: normalized);

      final isFirst = wallets.isEmpty;
      final model = WalletModel(
        id: walletId,
        name: name.trim().isEmpty ? 'Wallet' : name.trim(),
        publicKey: kp.address,
        createdAt: DateTime.now(),
        isDefault: isFirst,
      );

      // Update list and persist (ensure single default)
      final updated = <WalletModel>[...wallets];
      if (!isFirst) {
        // Keep existing default as-is; user can switch later
        updated.add(model);
      } else {
        updated.add(model);
      }
      // If first wallet, ensure it is default
      final normalizedList = isFirst
          ? [for (final w in updated) w.copyWith(isDefault: w.id == walletId)]
          : updated;

      wallets = List.unmodifiable(normalizedList);
      currentWallet = model.isDefault ? model : currentWallet;
      await _secure.saveWalletList(normalizedList);
      _notify();
      await refreshBalances();
    } catch (e) {
      debugPrint('WalletProvider.createWallet error: $e');
      _setError(e is ArgumentError ? e.message.toString() : 'Neuspješno kreiranje walleta');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> importFromMnemonic(String name, String mnemonic) async {
    _setLoading(true);
    try {
      final normalized = mnemonic.trim();
      if (!_crypto.validateMnemonic(normalized)) {
        throw ArgumentError('Neispravna recovery phrase');
      }
      final seed = _crypto.mnemonicToSeed(normalized);
      final kp = await _crypto.deriveKeypair(seed, accountIndex: 0);
      final walletId = _newWalletId();
      await _secure.savePrivateKey(walletId: walletId, privateKey: Uint8List.fromList(kp.secretKey));
      await _secure.saveMnemonic(walletId: walletId, mnemonic: normalized);

      final model = WalletModel(
        id: walletId,
        name: name.trim().isEmpty ? 'Wallet' : name.trim(),
        publicKey: kp.address,
        createdAt: DateTime.now(),
        isDefault: wallets.isEmpty,
      );

      final updated = wallets.isEmpty
          ? [model.copyWith(isDefault: true)]
          : [...wallets, model];

      wallets = List.unmodifiable(updated);
      // Keep current default unless this is the first wallet
      if (wallets.length == 1) currentWallet = model;
      await _secure.saveWalletList(updated);
      _notify();
      await refreshBalances();
    } catch (e) {
      debugPrint('WalletProvider.importFromMnemonic error: $e');
      _setError(e is ArgumentError ? e.message.toString() : 'Neuspješan uvoz iz recovery phrase');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> importFromPrivateKey(String name, String privateKey) async {
    _setLoading(true);
    try {
      final pkStr = privateKey.trim();
      if (pkStr.isEmpty) throw ArgumentError('Privatni ključ je prazan');
      Uint8List raw;
      try {
        raw = Uint8List.fromList(base58decode(pkStr));
      } catch (e) {
        throw ArgumentError('Neispravan Base58 format privatnog ključa');
      }

      Uint8List secret64;
      Uint8List public32;
      if (raw.length == 64) {
        secret64 = Uint8List.fromList(raw);
        public32 = Uint8List.fromList(raw.sublist(32, 64));
      } else if (raw.length == 32) {
        // Derive public key from 32-byte seed
        final algo = crypto.Ed25519();
        final keyPair = await algo.newKeyPairFromSeed(Uint8List.fromList(raw));
        final pub = await keyPair.extractPublicKey();
        public32 = Uint8List.fromList(pub.bytes);
        secret64 = Uint8List(64)
          ..setRange(0, 32, raw)
          ..setRange(32, 64, public32);
      } else {
        throw ArgumentError('Duljina privatnog ključa mora biti 32 ili 64 bajta');
      }

      final walletId = _newWalletId();
      await _secure.savePrivateKey(walletId: walletId, privateKey: secret64);

      final address = _crypto.publicKeyToBase58(public32);
      final model = WalletModel(
        id: walletId,
        name: name.trim().isEmpty ? 'Wallet' : name.trim(),
        publicKey: address,
        createdAt: DateTime.now(),
        isDefault: wallets.isEmpty,
      );

      final updated = wallets.isEmpty
          ? [model.copyWith(isDefault: true)]
          : [...wallets, model];
      wallets = List.unmodifiable(updated);
      if (wallets.length == 1) currentWallet = model;
      await _secure.saveWalletList(updated);
      _notify();
      await refreshBalances();
    } catch (e) {
      debugPrint('WalletProvider.importFromPrivateKey error: $e');
      _setError(e is ArgumentError ? e.message.toString() : 'Neuspješan uvoz iz privatnog ključa');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteWallet(String walletId) async {
    _setLoading(true);
    try {
      final existing = [...wallets];
      final idx = existing.indexWhere((w) => w.id == walletId);
      if (idx < 0) {
        _setError('Wallet nije pronađen');
        return;
      }

      // Remove secrets
      await _secure.deletePrivateKey(walletId: walletId);
      try {
        await _secure.deleteMnemonic(walletId: walletId);
      } catch (_) {
        // mnemonic may not exist; ignore
      }

      existing.removeAt(idx);

      // Determine next current/default wallet
      WalletModel? next;
      if (existing.isNotEmpty) {
        next = existing.firstWhere((w) => w.isDefault, orElse: () => existing.first);
        // Ensure exactly one default
        for (var i = 0; i < existing.length; i++) {
          existing[i] = existing[i].copyWith(isDefault: existing[i].id == next!.id);
        }
      }

      wallets = List.unmodifiable(existing);
      currentWallet = next;
      await _secure.saveWalletList(existing);
      if (currentWallet != null) {
        await refreshBalances();
      } else {
        solBalance = BigInt.zero;
        tokens = const [];
        _notify();
      }
    } catch (e) {
      debugPrint('WalletProvider.deleteWallet error: $e');
      _setError('Neuspješno brisanje walleta');
    } finally {
      _setLoading(false);
    }
  }

  void clearError() => _setError(null);

  @override
  void dispose() {
    _errorTimer?.cancel();
    _rpc.close();
    _disposed = true;
    super.dispose();
  }

  // ---------------- Internals ----------------

  String _newWalletId() => 'w_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  void _setLoading(bool v) {
    isLoading = v;
    _notify();
  }

  void _setError(String? message) {
    error = message;
    _notify();
    _errorTimer?.cancel();
    if (message != null && message.isNotEmpty) {
      _errorTimer = Timer(const Duration(seconds: 5), () {
        error = null;
        _notify();
      });
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
