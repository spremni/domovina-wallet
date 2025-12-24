import 'dart:math';
import 'dart:typed_data';
import 'package:domovina_wallet/models/wallet_model.dart';
import 'package:domovina_wallet/nav.dart';
import 'package:domovina_wallet/services/crypto_service.dart';
import 'package:domovina_wallet/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:domovina_wallet/widgets/app_button.dart';

class WalletCreationScreen extends StatefulWidget {
  const WalletCreationScreen({super.key});

  @override
  State<WalletCreationScreen> createState() => _WalletCreationScreenState();
}

class _WalletCreationScreenState extends State<WalletCreationScreen> with TickerProviderStateMixin {
  // Steps: 0 Intro, 1 Mnemonic, 2 Verify, 3 Name
  int _step = 0;
  bool _ack = false;
  String? _mnemonic;
  List<String> _words = const [];
  final _verifyCtrls = List.generate(3, (_) => TextEditingController());
  final _verifyFocus = List.generate(3, (_) => FocusNode());
  List<int> _verifyIdx = const [];
  String? _verifyError;
  final TextEditingController _nameCtrl = TextEditingController(text: 'Moj wallet');
  bool _biometrics = false; // Optional, not wired yet
  bool _saving = false;

  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _fadeController.forward();
  }

  @override
  void dispose() {
    for (final c in _verifyCtrls) c.dispose();
    for (final f in _verifyFocus) f.dispose();
    _nameCtrl.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goNext() {
    setState(() => _step += 1);
  }

  void _prepareMnemonic() {
    if (_mnemonic != null) return;
    final m = CryptoService.instance.generateMnemonic();
    final w = m.split(' ');
    setState(() {
      _mnemonic = m;
      _words = w;
    });
  }

  void _prepareVerification() {
    // Pick three distinct indices from 1..12
    final rnd = Random();
    final set = <int>{};
    while (set.length < 3) {
      set.add(rnd.nextInt(12) + 1); // 1..12
    }
    final idx = set.toList()..sort();
    setState(() {
      _verifyIdx = idx;
      _verifyError = null;
    });
  }

  bool get _verifyAllCorrect {
    if (_verifyIdx.length != 3 || _words.length != 12) return false;
    for (int i = 0; i < 3; i++) {
      final expected = _words[_verifyIdx[i] - 1];
      final got = _verifyCtrls[i].text.trim().toLowerCase();
      if (got != expected) return false;
    }
    return true;
  }

  Future<void> _copyMnemonic() async {
    if (_mnemonic == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: _mnemonic!));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery phrase kopiran u međuspremnik')));
    } catch (e) {
      debugPrint('Copy mnemonic failed: $e');
    }
  }

  String _genId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random();
    String hex(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return 'wlt_${now}_${hex(8)}';
  }

  Future<void> _completeSetup() async {
    if (_mnemonic == null) return;
    setState(() {
      _saving = true;
      _verifyError = null;
    });
    try {
      final seed = CryptoService.instance.mnemonicToSeed(_mnemonic!);
      final kp = await CryptoService.instance.deriveKeypair(seed);
      final publicKey = kp.address;

      final walletId = _genId();
      // Save private key (64 bytes) using secure storage (AES-GCM + keystore)
      await SecureStorageService.instance.savePrivateKey(walletId: walletId, privateKey: Uint8List.fromList(kp.secretKey));

      // Update wallet list metadata
      final wallets = await SecureStorageService.instance.getWalletList();
      final now = DateTime.now();
      final newWallet = WalletModel(id: walletId, name: _nameCtrl.text.trim().isEmpty ? 'Moj wallet' : _nameCtrl.text.trim(), publicKey: publicKey, createdAt: now, isDefault: wallets.isEmpty);
      // Ensure only one default
      final updated = <WalletModel>[];
      if (newWallet.isDefault) {
        updated.add(newWallet);
        updated.addAll(wallets.map((w) => w.copyWith(isDefault: false)));
      } else {
        updated.addAll(wallets);
        updated.add(newWallet);
      }
      await SecureStorageService.instance.saveWalletList(updated);

      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      debugPrint('Wallet setup failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Greška pri postavljanju walleta. Pokušajte ponovno.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kreiraj novi wallet'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), color: cs.onSurface, onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Padding(
            key: ValueKey(_step),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _buildStep(context, cs, text),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, ColorScheme cs, TextTheme text) {
    switch (_step) {
      case 0:
        return _StepIntro(
          ack: _ack,
          onAckChanged: (v) => setState(() => _ack = v),
          onNext: _ack
              ? () {
                  _prepareMnemonic();
                  _goNext();
                }
              : null,
        );
      case 1:
        return _StepMnemonic(
          words: _words,
          onCopy: _copyMnemonic,
          onNext: () {
            _prepareVerification();
            _goNext();
          },
        );
      case 2:
        return _StepVerify(
          words: _words,
          indices: _verifyIdx,
          ctrls: _verifyCtrls,
          error: _verifyError,
          onChanged: () => setState(() {}),
          onVerify: _verifyAllCorrect
              ? () {
                  setState(() => _verifyError = null);
                  _goNext();
                }
              : () => setState(() => _verifyError = 'Riječi se ne podudaraju. Provjerite i pokušajte ponovno.'),
        );
      case 3:
        return _StepFinalize(
          nameCtrl: _nameCtrl,
          biometrics: _biometrics,
          onBiometricsChanged: (v) => setState(() => _biometrics = v),
          saving: _saving,
          onFinish: _saving ? null : _completeSetup,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _StepIntro extends StatelessWidget {
  final bool ack;
  final ValueChanged<bool> onAckChanged;
  final VoidCallback? onNext;
  const _StepIntro({required this.ack, required this.onAckChanged, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text('Recovery phrase', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Vaše 12 riječi služe za oporavak walleta na novom uređaju.', style: text.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Ovo je JEDINI način za oporavak vašeg walleta. Ako izgubite frazu, nitko je ne može vratiti.', style: text.bodyMedium?.copyWith(color: cs.onSurface)),
          ),
        ]),
      ),
      const Spacer(),
      CheckboxListTile(
        value: ack,
        onChanged: (v) => onAckChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('Razumijem da moram sigurno pohraniti ove riječi', style: text.bodyMedium?.copyWith(color: cs.onSurface)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 12),
      AppButton(label: 'Prikaži recovery phrase', icon: Icons.visibility_outlined, useSecondaryAccent: true, onPressed: onNext),
    ]);
  }
}

class _StepMnemonic extends StatelessWidget {
  final List<String> words;
  final VoidCallback onCopy;
  final VoidCallback onNext;
  const _StepMnemonic({required this.words, required this.onCopy, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Zapišite svoje riječi', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700))),
        IconButton(onPressed: onCopy, icon: const Icon(Icons.copy_all_rounded), color: cs.onSurface),
      ]),
      const SizedBox(height: 8),
      Text('Zapišite i pohranite ovih 12 riječi na sigurno mjesto.', style: text.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      const SizedBox(height: 12),
      Expanded(
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.5),
          itemCount: words.length,
          itemBuilder: (context, i) {
            final idx = i + 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.primary.withValues(alpha: 0.15), width: 1)),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Text('$idx', style: text.labelMedium?.copyWith(color: cs.onSecondary, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(words[i], style: text.titleMedium?.copyWith(color: cs.onSurface), overflow: TextOverflow.ellipsis))
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.lock_outline, color: cs.error),
          const SizedBox(width: 10),
          Expanded(child: Text('NIKADA ne dijelite ove riječi s nikime!', style: text.bodyMedium?.copyWith(color: cs.onSurface))),
        ]),
      ),
      const SizedBox(height: 12),
      AppButton(label: 'Zapisao sam riječi', icon: Icons.check_circle_outline, useSecondaryAccent: true, onPressed: onNext),
    ]);
  }
}

class _StepVerify extends StatelessWidget {
  final List<String> words;
  final List<int> indices; // 1-based positions
  final List<TextEditingController> ctrls;
  final VoidCallback onVerify;
  final VoidCallback onChanged;
  final String? error;
  const _StepVerify({required this.words, required this.indices, required this.ctrls, required this.onVerify, required this.onChanged, this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final allFilled = ctrls.every((c) => c.text.trim().isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Potvrdite backup', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Unesite sljedeće riječi kako bismo provjerili da ste ih zapisali.', style: text.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      const SizedBox(height: 16),
      if (indices.length == 3)
        ...List.generate(3, (i) {
          final n = indices[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: ctrls[i],
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: 'Riječ #$n',
                hintText: 'Unesite riječ #$n',
                prefixIcon: const Icon(Icons.edit_outlined),
              ),
            ),
          );
        }),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: text.labelMedium?.copyWith(color: cs.error))),
      const Spacer(),
      AppButton(label: 'Potvrdi', icon: Icons.verified_outlined, useSecondaryAccent: true, onPressed: allFilled ? onVerify : null),
    ]);
  }
}

class _StepFinalize extends StatelessWidget {
  final TextEditingController nameCtrl;
  final bool biometrics;
  final ValueChanged<bool> onBiometricsChanged;
  final bool saving;
  final VoidCallback? onFinish;
  const _StepFinalize({required this.nameCtrl, required this.biometrics, required this.onBiometricsChanged, required this.saving, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zadnji korak', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Imenujte svoj wallet i po želji omogućite biometrijsku zaštitu.', style: text.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      const SizedBox(height: 16),
      TextField(
        controller: nameCtrl,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Naziv walleta', hintText: 'npr. Moj wallet', prefixIcon: Icon(Icons.wallet_outlined)),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        value: biometrics,
        onChanged: onBiometricsChanged,
        title: Text('Omogući biometrijsko otključavanje', style: text.bodyMedium?.copyWith(color: cs.onSurface)),
        subtitle: Text('Preporučeno radi lakšeg i sigurnijeg pristupa', style: text.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.7))),
        secondary: const Icon(Icons.fingerprint),
        contentPadding: EdgeInsets.zero,
      ),
      const Spacer(),
      if (saving)
        Center(child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text('Spremanje...', style: text.labelLarge)])
        )
      else
        AppButton(label: 'Završi postavljanje', icon: Icons.rocket_launch_outlined, useSecondaryAccent: true, onPressed: onFinish),
    ]);
  }
}
