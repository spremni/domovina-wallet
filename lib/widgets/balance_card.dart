import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// A reusable, animated balance card with glassmorphism, count-up animation,
/// optional fiat display, shimmering skeleton, and pull-down-to-refresh gesture.
class BalanceCard extends StatefulWidget {
  /// Balance in lamports for SOL (1e9 lamports = 1 SOL)
  final BigInt balance;

  /// Token symbol, defaults to SOL
  final String symbol;

  /// Optional fiat value for the current balance (e.g., EUR total)
  final double? fiatValue;

  /// Fiat currency code, e.g., EUR, USD. Defaults to EUR.
  final String fiatCurrency;

  /// When true, shows a shimmer loading state.
  final bool isLoading;

  /// Called when the user performs a pull-down gesture on the card.
  final VoidCallback? onRefresh;

  const BalanceCard({super.key, required this.balance, this.symbol = 'SOL', this.fiatValue, this.fiatCurrency = 'EUR', this.isLoading = false, this.onRefresh});

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> with SingleTickerProviderStateMixin {
  static const int _lamportsPerSol = 1000000000; // 1e9

  late AnimationController _shimmerCtrl;
  double _fromSol = 0;
  double _toSol = 0;

  @override
  void initState() {
    super.initState();
    _toSol = _lamportsToSol(widget.balance);
    _fromSol = _toSol; // first paint: no animation jump
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void didUpdateWidget(covariant BalanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSol = _lamportsToSol(widget.balance);
    if (newSol != _toSol) {
      // Start animating from previous displayed value to new value
      _fromSol = _toSol;
      _toSol = newSol;
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  double _lamportsToSol(BigInt lamports) => lamports.toDouble() / _lamportsPerSol;

  // Format a SOL amount with up to 9 decimals, trim trailing zeros, and add thousand separators.
  String _formatSol(double sol, {String symbol = 'SOL'}) {
    final isNeg = sol < 0;
    final abs = sol.abs();
    final fixed = abs.toStringAsFixed(9); // max precision for SOL
    final parts = fixed.split('.');
    String intPart = parts[0];
    String fracPart = parts.length > 1 ? parts[1] : '';

    // Trim trailing zeros from fractional part
    while (fracPart.isNotEmpty && fracPart.endsWith('0')) {
      fracPart = fracPart.substring(0, fracPart.length - 1);
    }
    if (fracPart.isEmpty) return '${isNeg ? '-' : ''}${_thousands(intPart)} $symbol';
    return '${isNeg ? '-' : ''}${_thousands(intPart)}.$fracPart $symbol';
  }

  // Insert thousand separators (comma) into integer part
  String _thousands(String digits) {
    final buf = StringBuffer();
    int count = 0;
    for (int i = digits.length - 1; i >= 0; i--) {
      buf.write(digits[i]);
      count++;
      if (count % 3 == 0 && i != 0) buf.write(',');
    }
    return buf.toString().split('').reversed.join();
  }

  String _currencySymbol(String code) {
    final upper = code.toUpperCase();
    if (upper == 'EUR') return '€';
    if (upper == 'USD') return '4'.substring(1); // Produces '$' without escaping
    if (upper == 'HRK') return 'kn';
    return upper;
  }

  String _formatFiat(double amount, String code) {
    final sym = _currencySymbol(code);
    final fixed = amount.isFinite ? amount.abs().toStringAsFixed(2) : '—';
    final parts = fixed.split('.');
    final intPart = _thousands(parts[0]);
    final frac = parts.length > 1 ? parts[1] : '00';
    return '$sym $intPart.$frac';
  }

  void _handleDragEnd(DragEndDetails d) {
    if (widget.onRefresh == null) return;
    // Consider a downward fling as refresh intent
    if ((d.primaryVelocity ?? 0) > 300) widget.onRefresh!.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final content = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _fromSol, end: _toSol),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutQuad,
                switchOutCurve: Curves.easeInQuad,
                child: Text(
                  _formatSol(value, symbol: widget.symbol),
                  key: ValueKey<String>('bal_${value.toStringAsFixed(6)}_${widget.symbol}'),
                  style: text.headlineLarge?.copyWith(color: cs.onSurface),
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            widget.fiatValue == null ? '≈ ${_currencySymbol(widget.fiatCurrency)} —' : '≈ ${_formatFiat(widget.fiatValue!, widget.fiatCurrency)}',
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ]);
      },
    );

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16), width: 1),
        gradient: LinearGradient(
          colors: [cs.surface.withValues(alpha: 0.35), cs.surfaceContainerHighest.withValues(alpha: 0.28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(children: [
              // Pull-down indicator
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
              ]),
              const SizedBox(height: 6),
              // Title + symbol badge
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Ukupno stanje', style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.primary.withValues(alpha: 0.35))),
                  child: Row(children: [
                    Icon(Icons.hexagon, size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(widget.symbol, style: text.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              content,
            ]),
          ),
        ),
      ),
    );

    final shimmer = _Shimmer(
      controller: _shimmerCtrl,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );

    return GestureDetector(onVerticalDragEnd: _handleDragEnd, child: widget.isLoading ? shimmer : card);
  }
}

class _Shimmer extends StatelessWidget {
  final AnimationController controller;
  final Widget child;
  const _Shimmer({required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (rect) {
            // sweep from left to right
            final width = rect.width;
            final dx = (controller.value * (width + 200)) - 200;
            return LinearGradient(
              begin: Alignment(-1 + dx / width, 0),
              end: Alignment((dx + 200) / width, 0),
              colors: [
                cs.surface.withValues(alpha: 0.2),
                cs.onSurface.withValues(alpha: 0.08),
                cs.surface.withValues(alpha: 0.2),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}
