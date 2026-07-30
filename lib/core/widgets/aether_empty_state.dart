import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/icon_size.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';

class AetherEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AetherEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AetherSpace.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cfg.bgHover,
                  shape: BoxShape.circle,
                  border: Border.all(color: cfg.borderSubtle),
                ),
                child: Icon(
                  icon,
                  size: AetherIconSize.hero,
                  color: cfg.textTertiary,
                ),
              ),
              const SizedBox(height: AetherSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AetherType.titleStyle(cfg.textPrimary),
              ),
              if (message != null) ...[
                const SizedBox(height: AetherSpace.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AetherType.bodyStyle(cfg.textSecondary),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AetherSpace.xl),
                AetherButton.primary(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AetherLoading extends StatelessWidget {
  final String? message;
  final double size;

  const AetherLoading({
    super.key,
    this.message,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AetherProgress.circular(size: size, strokeWidth: 2.6),
          if (message != null) ...[
            const SizedBox(height: AetherSpace.lg),
            Text(message!, style: AetherType.bodySmStyle(cfg.textSecondary)),
          ],
        ],
      ),
    );
  }
}
