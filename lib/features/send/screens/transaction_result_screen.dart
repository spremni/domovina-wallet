import 'dart:async';
import 'dart:math' as math;

import 'package:domovina_wallet/core/constants/solana_constants.dart';
import 'package:domovina_wallet/core/utils/formatters.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Arguments passed to TransactionResultScreen via GoRouter.extra
class TransactionResultArgs {
  final bool success;
  final String recipientAddress;
  final BigInt amountBase;
  final TokenBalance token;
  final String? signature; // present when success
  final String? rawError; // present when failure

  const TransactionResultArgs({
    required this.success,
    required this.recipientAddress,
    required this.amountBase,
    required this.token,
    this.signature,
    this.rawError,
  });
}

class TransactionResultScreen extends StatefulWidget {
  final TransactionResultArgs? args;
  const TransactionResultScreen({super.key, this.args});

  @override
  State<TransactionResultScreen> createState() => _TransactionResultScreenState();
}

class _TransactionResultScreenState extends State<TransactionResultScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleIn;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scaleIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    scheduleMicrotask(() => _controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatAmount(TransactionResultArgs a) {
    final decimals = a.token.decimals;
    final scale = math.pow(10, decimals).toDouble();
    final ui = a.amountBase.toDouble() / scale;
    final shown = ui.toStringAsFixed(math.min(6, decimals));
    final sym = a.token.symbol.isEmpty ? (a.token.isNative ? 'SOL' : '') : a.token.symbol;
    return '$shown ${sym.isEmpty ? 'TOKEN' : sym}';
  }

  String _mapError(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Došlo je do nepoznate greške.';
    final lc = raw.toLowerCase();
    if (lc.contains('insufficient') || lc.contains('insuff') || lc.contains('balance')) {
      return 'Nedovoljno sredstava za ovu transakciju.';
    }
    if (lc.contains('blockhash') || lc.contains('timeout') || lc.contains('timed out')) {
      return 'Isteklo je vrijeme potvrde transakcije. Pokušajte ponovno.';
    }
    if (lc.contains('address') || lc.contains('recipient') || lc.contains('base58') || lc.contains('invalid')) {
      return 'Neispravna adresa primatelja.';
    }
    if (lc.contains('network') || lc.contains('rpc') || lc.contains('connection') || lc.contains('node')) {
      return 'Greška mreže. Provjerite vezu i pokušajte ponovno.';
    }
    return raw; // fallback to raw message
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label kopiran')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final a = widget.args;

    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rezultat')),
        body: Center(child: Text('Nema podataka o transakciji', style: text.bodyLarge?.copyWith(color: cs.onSurfaceVariant))),
      );
    }

    final isSuccess = a.success;
    final amountStr = _formatAmount(a);
    final recipientShort = Formatters.shortAddress(a.recipientAddress);
    final signature = a.signature ?? '';
    final explorerUrl = isSuccess && signature.isNotEmpty
        ? 'https://explorer.solana.com/tx/$signature${SolanaConstants.isMainnet ? '' : '?cluster=devnet'}'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSuccess ? 'Uspjeh' : 'Neuspjeh'),
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back, color: cs.onSurface)),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated icon + subtle confetti on success
                ScaleTransition(
                  scale: _scaleIn,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: (isSuccess ? cs.inversePrimary : cs.error).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: (isSuccess ? cs.inversePrimary : cs.error).withValues(alpha: 0.35), width: 2),
                        ),
                        child: Icon(isSuccess ? Icons.check_rounded : Icons.close_rounded, size: 72, color: isSuccess ? cs.inversePrimary : cs.error),
                      ),
                      if (isSuccess) _Confetti(radius: 68, color: cs.secondary),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                FadeTransition(
                  opacity: _fadeIn,
                  child: Column(children: [
                    Text(isSuccess ? 'Transakcija uspješna!' : 'Transakcija neuspješna', style: text.headlineSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (isSuccess) ...[
                      Text('Poslano: $amountStr', style: text.titleMedium?.copyWith(color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text('Primatelj: $recipientShort', style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      if (signature.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
                          child: Row(children: [
                            Expanded(child: Text('Potpis: ${Formatters.shortAddress(signature)}', style: text.labelLarge?.copyWith(color: cs.onSurface))),
                            IconButton(onPressed: () => _copy(signature, 'Potpis'), icon: Icon(Icons.copy, color: cs.primary)),
                          ]),
                        ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(_mapError(a.rawError), textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: cs.onSurface)),
                    ],
                  ]),
                ),

                const SizedBox(height: 22),

                if (isSuccess && explorerUrl != null) ...[
                  TextButton.icon(
                    onPressed: () => _copy(explorerUrl, 'Link'),
                    icon: Icon(Icons.open_in_new, color: cs.primary),
                    label: Text('Pogledaj na Exploreru', style: text.labelLarge?.copyWith(color: cs.primary)),
                  ),
                  const SizedBox(height: 10),
                ],

                // Actions
                if (isSuccess)
                  AppButton(label: 'Gotovo', icon: Icons.check, onPressed: () => context.go('/'))
                else ...[
                  AppButton(label: 'Pokušaj ponovo', icon: Icons.refresh_rounded, onPressed: () => context.go('/send')),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.pop(), child: Text('Natrag', style: text.titleSmall?.copyWith(color: cs.onSurface))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Confetti extends StatefulWidget {
  final double radius;
  final Color color;
  const _Confetti({required this.radius, required this.color});

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            final parts = <Widget>[];
            for (int i = 0; i < 10; i++) {
              final angle = (i / 10.0) * 2 * math.pi + t * 2 * math.pi;
              final r = widget.radius + (math.sin(t * 6 + i) * 6);
              final dx = r * math.cos(angle);
              final dy = r * math.sin(angle);
              parts.add(Positioned(
                left: 60 + dx,
                top: 60 + dy,
                child: Transform.rotate(
                  angle: angle,
                  child: Icon(Icons.circle, size: 6 + (i % 3).toDouble(), color: i.isEven ? widget.color : cs.primary),
                ),
              ));
            }
            return Stack(children: parts);
          },
        ),
      ),
    );
  }
}
