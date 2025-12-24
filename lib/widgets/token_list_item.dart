import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domovina_wallet/models/token_model.dart';
import 'package:domovina_wallet/core/constants/token_registry.dart';
import 'package:domovina_wallet/core/theme/app_theme.dart';

/// A single row item displaying a token with icon, name/symbol, balance and fiat value.
///
/// - Left: 36x36 rounded icon (mapped from TokenRegistry.iconKey). Fallback to first letter.
/// - Center: Name (bold) and symbol (secondary color)
/// - Right: Balance (right aligned) and fiat value (smaller, secondary)
///
/// Interaction: tap triggers [onTap] and light haptic feedback. Uses a subtle pressed highlight
/// instead of a large splash to keep the UI modern and minimal.
class TokenListItem extends StatelessWidget {
  final TokenBalance token;
  final VoidCallback? onTap;

  const TokenListItem({super.key, required this.token, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Compute display values
    final amount = token.uiAmount;
    final decimals = token.decimals.clamp(0, 9);
    // For UI, limit to a reasonable number of fraction digits (2-6 depending on token)
    final fraction = amount == 0
        ? 2
        : amount >= 1000
            ? 2
            : amount >= 1
                ? (decimals.clamp(2, 4))
                : (decimals.clamp(3, 6));
    final amountText = amount.toStringAsFixed(fraction);

    // Prefer EUR if present, fallback to USD, else null
    final eur = token.eurValue;
    final usd = token.usdValue;
    final fiatText = eur != null
        ? '≈ € ${eur.abs().toStringAsFixed(2)}'
        : usd != null
            ? '≈ \$ ${usd.abs().toStringAsFixed(2)}'
            : '≈ —';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap?.call();
              },
        borderRadius: BorderRadius.circular(AppRadius.md),
        // Subtle highlight only; avoid heavy splash.
        splashColor: Theme.of(context).highlightColor.withValues(alpha: 0.05),
        highlightColor: Theme.of(context).highlightColor.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TokenIcon(size: 36, token: token),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      token.name.isNotEmpty ? token.name : token.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      token.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    amountText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fiatText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TokenIcon extends StatelessWidget {
  final double size;
  final TokenBalance token;

  const _TokenIcon({required this.size, required this.token});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size / 2);

    final iconData = _iconForToken(token);
    final hasIcon = iconData != null;
    final bg = cs.surfaceContainerHighest;
    final fg = cs.onSurface;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: bg,
        border: Border.all(color: cs.outline.withValues(alpha: 0.15), width: 1),
      ),
      alignment: Alignment.center,
      child: hasIcon
          ? Icon(iconData, size: size * 0.65, color: cs.primary)
          : Text(
              (token.symbol.isNotEmpty ? token.symbol[0] : '•').toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: fg),
            ),
    );
  }

  IconData? _iconForToken(TokenBalance t) {
    // First try registry mapping by mint or symbol to get iconKey.
    TokenInfo? info;
    if (t.mint != null) {
      info = TokenRegistry.byMint(t.mint!);
    }
    info ??= TokenRegistry.bySymbol(t.symbol);

    switch (info?.iconKey) {
      case 'solana':
        return Icons.auto_awesome; // stylized sparkle as placeholder for Solana
      case 'euro':
        return Icons.euro;
      case 'dollar':
        return Icons.attach_money;
      case 'hr_checkerboard':
        return Icons.shield; // Croatian shield motif
      default:
        return null;
    }
  }
}

/// Optional divider widget to place between TokenListItem rows.
class TokenListItemDivider extends StatelessWidget {
  const TokenListItemDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 52), // indent under text (36 icon + 12 gap + 4 padding)
      child: Container(
        height: 1,
        color: cs.outline.withValues(alpha: 0.08),
      ),
    );
  }
}
