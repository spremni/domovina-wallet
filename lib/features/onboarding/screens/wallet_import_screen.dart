import 'dart:math';
import 'dart:typed_data';

import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/crypto_service.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:solana/base58.dart' show base58decode;
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:cryptography/cryptography.dart' as crypto;

class WalletImportScreen extends StatefulWidget {
  const WalletImportScreen({super.key});

  @override
  State<WalletImportScreen> createState() => _WalletImportScreenState();
}

class _WalletImportScreenState extends State<WalletImportScreen> with SingleTickerProviderStateMixin {
  final _seedController = TextEditingController();
  final _pkController = TextEditingController();
  final _nameController = TextEditingController(text: 'Uvezeni wallet');

  bool _ackSecurity = false; // for PK tab warning acknowledgement
  bool _isImporting = false;
  bool _showSuccess = false;

  String? _seedError;
  String? _pkError;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _seedController.addListener(_validateSeed);
    _pkController.addListener(_validatePk);
  }

  @override
  void dispose() {
    _seedController.dispose();
    _pkController.dispose();
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // UI Helpers
  int _seedWordCount() {
    final text = _seedController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  void _validateSeed() {
    final words = _seedWordCount();
    final text = _seedController.text.trim();
    if (words == 0) {
      setState(() => _seedError = null);
      return;
    }
    // Only validate when plausible word counts
    final plausible = words == 12 || words == 24;
    if (!plausible) {
      setState(() => _seedError = 'Recovery phrase mora imati 12 ili 24 riječi');
      return;
    }
    final valid = CryptoService.instance.validateMnemonic(text);
    setState(() => _seedError = valid ? null : 'Neispravna recovery phrase');
  }

  void _validatePk() {
    final s = _pkController.text.trim();
    if (s.isEmpty) {
      setState(() => _pkError = null);
      return;
    }
    final re = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    if (!re.hasMatch(s)) {
      setState(() => _pkError = 'Neispravan format (mora biti base58)');
      return;
    }
    try {
      final bytes = base58decode(s);
      if (bytes.length != 64 && bytes.length != 32) {
        setState(() => _pkError = 'Privatni ključ mora biti 32 ili 64 bajta');
      } else {
        setState(() => _pkError = null);
      }
    } catch (e) {
      setState(() => _pkError = 'Ne mogu dekodirati ključ');
    }
  }

  Future<void> _pasteTo(TextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) c.text = data!.text!.trim();
  }

  String _genId() {
    final r = Random.secure();
    final n = r.nextInt(0xFFFFFF);
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${n.toRadixString(16)}';
  }

  Future<void> _importFromSeed() async {
    final mnemonic = _seedController.text.trim();
    final words = _seedWordCount();
    final plausible = words == 12 || words == 24;
    final valid = plausible && CryptoService.instance.validateMnemonic(mnemonic);
    if (!valid) {
      setState(() => _seedError = 'Neispravna recovery phrase');
      return;
    }
    setState(() => _isImporting = true);
    try {
      final seed = CryptoService.instance.mnemonicToSeed(mnemonic);
      final kp = await CryptoService.instance.deriveKeypair(seed);
      final walletId = _genId();

      // Save secret key and mnemonic securely
      await SecureStorageService.instance.savePrivateKey(walletId: walletId, privateKey: Uint8List.fromList(kp.secretKey));
      await SecureStorageService.instance.saveMnemonic(walletId: walletId, mnemonic: mnemonic);

      await _finishImport(addressBytes: kp.publicKey, walletId: walletId);
    } catch (e) {
      debugPrint('Import from seed failed: $e');
      if (mounted) {
        setState(() => _seedError = 'Dogodila se greška prilikom uvoza. Pokušajte ponovno.');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importFromPrivateKey() async {
    final s = _pkController.text.trim();
    if (s.isEmpty || _pkError != null || !_ackSecurity) return;
    setState(() => _isImporting = true);
    try {
      final decoded = base58decode(s);
      Uint8List secret64;
      Uint8List public32;
      if (decoded.length == 64) {
        // Use provided 64-byte secret; recompute public to be safe
        final private32 = Uint8List.fromList(decoded.sublist(0, 32));
        final algo = crypto.Ed25519();
        final keyPair = await algo.newKeyPairFromSeed(private32);
        final pub = await keyPair.extractPublicKey();
        public32 = Uint8List.fromList(pub.bytes);
        secret64 = Uint8List.fromList(decoded);
      } else if (decoded.length == 32) {
        final private32 = Uint8List.fromList(decoded);
        final algo = crypto.Ed25519();
        final keyPair = await algo.newKeyPairFromSeed(private32);
        final pub = await keyPair.extractPublicKey();
        public32 = Uint8List.fromList(pub.bytes);
        secret64 = Uint8List(64)
          ..setRange(0, 32, private32)
          ..setRange(32, 64, public32);
      } else {
        setState(() => _pkError = 'Privatni ključ mora biti 32 ili 64 bajta');
        return;
      }

      final walletId = _genId();
      await SecureStorageService.instance.savePrivateKey(walletId: walletId, privateKey: secret64);
      await _finishImport(addressBytes: public32, walletId: walletId);
    } catch (e) {
      debugPrint('Import from private key failed: $e');
      if (mounted) setState(() => _pkError = 'Neuspješan uvoz privatnog ključa');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _finishImport({required Uint8List addressBytes, required String walletId}) async {
    final address = CryptoService.instance.publicKeyToBase58(addressBytes);
    final now = DateTime.now();
    var wallet = WalletModel(id: walletId, name: _nameController.text.trim().isEmpty ? 'Uvezeni wallet' : _nameController.text.trim(), publicKey: address, createdAt: now, isDefault: true);

    // Persist into wallet list (set as default)
    final existing = await SecureStorageService.instance.getWalletList();
    final updated = existing.map((w) => w.copyWith(isDefault: false)).toList(growable: true)..add(wallet);
    await SecureStorageService.instance.saveWalletList(updated);

    if (!mounted) return;
    setState(() => _showSuccess = true);

    await Future.delayed(const Duration(milliseconds: 300));
    await _askNameAndBiometrics(initial: wallet.name).then((result) async {
      if (result != null) {
        final newName = result.$1;
        // biometricsEnabled is result.$2 (not enforced yet)
        wallet = wallet.copyWith(name: newName);
        // Update saved list with new name
        final list = await SecureStorageService.instance.getWalletList();
        final replaced = list.map((w) => w.id == wallet.id ? wallet : w).toList(growable: false);
        await SecureStorageService.instance.saveWalletList(replaced);
      }
    });

    if (!mounted) return;
    // Navigate to main wallet/home
    context.go(AppRoutes.home);
  }

  Future<(String, bool)?> _askNameAndBiometrics({required String initial}) async {
    final cs = Theme.of(context).colorScheme;
    final nameController = TextEditingController(text: initial);
    bool biometrics = true;
    final result = await showDialog<(String, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.check_circle, color: cs.secondary),
                const SizedBox(width: 8),
                Text('Wallet uspješno uvezen', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: cs.onSurface)),
              ]),
              const SizedBox(height: 12),
              Text('Naziv walleta', style: Theme.of(ctx).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Moj wallet',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.fingerprint, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Omogući biometriju za otključavanje', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: cs.onSurface))),
                Switch(value: biometrics, onChanged: (v) => biometrics = v),
              ]),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(label: 'Nastavi', icon: Icons.arrow_forward, onPressed: () => Navigator.of(ctx).pop((nameController.text.trim().isEmpty ? 'Moj wallet' : nameController.text.trim(), biometrics)), useSecondaryAccent: true),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uvezi postojeći wallet'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: cs.secondary,
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurfaceVariant,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              tabs: const [
                Tab(text: 'Recovery phrase'),
                Tab(text: 'Privatni ključ'),
              ],
            ),
          ),
        ),
      ),
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface, cs.surfaceContainerHighest.withValues(alpha: 0.2)],
            ),
          ),
        ),
        TabBarView(
          controller: _tabController,
          children: [
            _SeedTab(
              controller: _seedController,
              errorText: _seedError,
              wordCount: _seedWordCount(),
              onPaste: () => _pasteTo(_seedController),
              onImport: _isImporting ? null : _importFromSeed,
              isImporting: _isImporting,
            ),
            _PkTab(
              controller: _pkController,
              errorText: _pkError,
              onPaste: () => _pasteTo(_pkController),
              onToggleAck: (v) => setState(() => _ackSecurity = v),
              ackSecurity: _ackSecurity,
              onImport: _isImporting ? null : _importFromPrivateKey,
              isImporting: _isImporting,
            ),
          ],
        ),
        // Success overlay
        IgnorePointer(
          ignoring: !_showSuccess,
          child: AnimatedOpacity(
            opacity: _showSuccess ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 400),
                  scale: _showSuccess ? 1 : 0.9,
                  curve: Curves.easeOutBack,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 64, color: cs.secondary),
                        const SizedBox(height: 12),
                        Text('Uvoz uspješan', style: tt.titleLarge?.copyWith(color: cs.onSurface)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SeedTab extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final int wordCount;
  final VoidCallback onPaste;
  final VoidCallback? onImport;
  final bool isImporting;
  const _SeedTab({required this.controller, required this.errorText, required this.wordCount, required this.onPaste, required this.onImport, required this.isImporting});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final valid = (wordCount == 12 || wordCount == 24) && errorText == null && controller.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Unesite 12 ili 24 riječi recovery phrase', style: tt.titleMedium?.copyWith(color: cs.onSurface)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            decoration: const InputDecoration.collapsed(hintText: 'word1 word2 word3 ...'),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
            child: Row(children: [
              Icon(Icons.format_list_numbered, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('$wordCount riječi', style: tt.labelMedium?.copyWith(color: cs.primary)),
            ]),
          ),
          const Spacer(),
          TextButton.icon(onPressed: onPaste, icon: Icon(Icons.paste, color: cs.primary), label: Text('Zalijepi', style: tt.labelLarge?.copyWith(color: cs.primary))),
        ]),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.error_outline, color: cs.error, size: 18), const SizedBox(width: 6), Expanded(child: Text(errorText!, style: tt.bodySmall?.copyWith(color: cs.error)))]),
        ],
        const SizedBox(height: 16),
        AppButton(label: 'Uvezi wallet', icon: Icons.download, onPressed: valid && !isImporting ? onImport : null, useSecondaryAccent: true),
      ]),
    );
  }
}

class _PkTab extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onPaste;
  final ValueChanged<bool> onToggleAck;
  final bool ackSecurity;
  final VoidCallback? onImport;
  final bool isImporting;
  const _PkTab({required this.controller, required this.errorText, required this.onPaste, required this.onToggleAck, required this.ackSecurity, required this.onImport, required this.isImporting});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canImport = controller.text.trim().isNotEmpty && errorText == null && ackSecurity;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Unesite privatni ključ (base58)', style: tt.titleMedium?.copyWith(color: cs.onSurface)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 2,
            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Base58 privatni ključ (32 ili 64 bajta)')
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(onPressed: onPaste, icon: Icon(Icons.paste, color: cs.primary), label: Text('Zalijepi', style: tt.labelLarge?.copyWith(color: cs.primary))),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.error.withValues(alpha: 0.2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, color: cs.error),
            const SizedBox(width: 10),
            Expanded(child: Text('Uvoz privatnog ključa nosi sigurnosne rizike. Preporučujemo uvoz preko recovery phrase.', style: tt.bodySmall?.copyWith(color: cs.onSurface))),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Switch(value: ackSecurity, onChanged: onToggleAck),
          const SizedBox(width: 8),
          Expanded(child: Text('Razumijem rizike', style: tt.bodyMedium?.copyWith(color: cs.onSurface))),
        ]),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.error_outline, color: cs.error, size: 18), const SizedBox(width: 6), Expanded(child: Text(errorText!, style: tt.bodySmall?.copyWith(color: cs.error)))]),
        ],
        const SizedBox(height: 16),
        AppButton(label: 'Uvezi wallet', icon: Icons.download, onPressed: canImport && !isImporting ? onImport : null, useSecondaryAccent: true),
      ]),
    );
  }
}
