import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';

/// Section label used in settings and form groups.
class AetherSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const AetherSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: padding ??
          const EdgeInsets.only(
            top: AetherSpace.lg,
            bottom: AetherSpace.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AetherType.labelStyle(cfg.textSecondary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AetherSpace.xxs),
                  Text(
                    subtitle!,
                    style: AetherType.bodySmStyle(cfg.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Horizontal label + control row for dense settings forms.
class AetherFormRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget child;
  final double labelWidth;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry? padding;

  const AetherFormRow({
    super.key,
    required this.label,
    required this.child,
    this.description,
    this.labelWidth = 120,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: AetherSpace.sm),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          SizedBox(
            width: labelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AetherType.bodyStyle(cfg.textPrimary)),
                if (description != null) ...[
                  const SizedBox(height: AetherSpace.xxs),
                  Text(
                    description!,
                    style: AetherType.captionStyle(cfg.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AetherSpace.lg),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Thin horizontal rule using theme border token.
class AetherDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final EdgeInsetsGeometry? margin;

  const AetherDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Container(
      margin: margin ??
          const EdgeInsets.symmetric(vertical: AetherSpace.md),
      child: Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: endIndent,
        color: cfg.borderSubtle,
      ),
    );
  }
}
