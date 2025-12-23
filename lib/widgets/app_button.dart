import 'package:flutter/material.dart';

/// A high-contrast primary action button with pill shape
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool secondary;

  const AppButton({super.key, required this.label, this.icon, this.onPressed, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = secondary ? Colors.transparent : cs.primary;
    final fg = secondary ? cs.primary : cs.onPrimary;
    final side = secondary ? BorderSide(color: cs.primary, width: 1) : BorderSide.none;

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
