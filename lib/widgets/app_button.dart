import 'package:flutter/material.dart';

/// A high-contrast action button with pill shape
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool secondary;
  /// When true, uses ColorScheme.secondary for filled background instead of primary.
  /// Useful when brand accents prefer the secondary color (e.g., Croatian red).
  final bool useSecondaryAccent;

  const AppButton({super.key, required this.label, this.icon, this.onPressed, this.secondary = false, this.useSecondaryAccent = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color baseBg = useSecondaryAccent ? cs.secondary : cs.primary;
    final Color baseFg = useSecondaryAccent ? cs.onSecondary : cs.onPrimary;
    final bg = secondary ? Colors.transparent : baseBg;
    final fg = secondary ? (useSecondaryAccent ? cs.secondary : cs.primary) : baseFg;
    final side = secondary ? BorderSide(color: useSecondaryAccent ? cs.secondary : cs.primary, width: 1) : BorderSide.none;

    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) Icon(icon, color: fg, size: 18),
      if (icon != null) const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    ]);

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.4),
        disabledForegroundColor: fg.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: side),
        elevation: 0,
      ),
      child: child,
    );
  }
}
