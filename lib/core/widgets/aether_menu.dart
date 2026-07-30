import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/icon_size.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';

/// One entry in an [showAetherMenu] popup.
class AetherMenuItem<T> {
  final T? value;
  final String label;
  final IconData? icon;
  final bool destructive;
  final bool warning;
  final bool enabled;
  final bool isDivider;
  final String? shortcut;

  const AetherMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.warning = false,
    this.enabled = true,
    this.shortcut,
  }) : isDivider = false;

  const AetherMenuItem.divider()
      : value = null,
        label = '',
        icon = null,
        destructive = false,
        warning = false,
        enabled = false,
        isDivider = true,
        shortcut = null;
}

/// Desktop/context popup menu with design-system motion and colors.
Future<T?> showAetherMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AetherMenuItem<T>> items,
  double minWidth = 200,
  double maxWidth = 320,
  bool useRootNavigator = true,
}) {
  assert(items.any((item) => !item.isDivider), 'Menu needs at least one action');

  final overlay = Overlay.of(context, rootOverlay: useRootNavigator).context.findRenderObject() as RenderBox;
  final overlaySize = overlay.size;
  final local = overlay.globalToLocal(globalPosition);
  final position = RelativeRect.fromLTRB(
    local.dx,
    local.dy,
    overlaySize.width - local.dx,
    overlaySize.height - local.dy,
  );

  final cfg = context.tokens;
  final enter = AetherMotion.duration(context, AetherMotion.fast);
  final leave = AetherMotion.exitOf(context, AetherMotion.fast);
  final fromScale = AetherMotion.fromScale(context, AetherMotion.popoverFromScale);

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _AetherMenuRoute<T>(
      position: position,
      items: items,
      minWidth: minWidth,
      maxWidth: maxWidth,
      barrierColor: Colors.transparent,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      enterDuration: enter,
      exitDuration: leave,
      fromScale: fromScale,
      cfg: cfg,
    ),
  );
}

/// Convenience: open a menu from a widget's bottom-left (for trailing buttons).
Future<T?> showAetherMenuFromRect<T>({
  required BuildContext context,
  required Rect globalRect,
  required List<AetherMenuItem<T>> items,
  double minWidth = 180,
  double maxWidth = 280,
}) {
  return showAetherMenu<T>(
    context: context,
    globalPosition: Offset(globalRect.left, globalRect.bottom + 4),
    items: items,
    minWidth: minWidth,
    maxWidth: maxWidth,
  );
}

class _AetherMenuRoute<T> extends PopupRoute<T> {
  _AetherMenuRoute({
    required this.position,
    required this.items,
    required this.minWidth,
    required this.maxWidth,
    required this.barrierColor,
    required this.barrierLabel,
    required this.enterDuration,
    required this.exitDuration,
    required this.fromScale,
    required this.cfg,
  });

  final RelativeRect position;
  final List<AetherMenuItem<T>> items;
  final double minWidth;
  final double maxWidth;
  @override
  final Color barrierColor;
  @override
  final String barrierLabel;
  final Duration enterDuration;
  final Duration exitDuration;
  final double fromScale;
  final AppThemeConfig cfg;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => enterDuration;

  @override
  Duration get reverseTransitionDuration => exitDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _AetherMenuLayout(position),
      child: _AetherMenuPanel<T>(
        items: items,
        minWidth: minWidth,
        maxWidth: maxWidth,
        cfg: cfg,
        onSelect: (value) => Navigator.of(context).pop(value),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (enterDuration == Duration.zero && exitDuration == Duration.zero) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AetherMotion.out,
      reverseCurve: AetherMotion.out,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: Alignment.topLeft,
        scale: Tween<double>(begin: fromScale, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class _AetherMenuLayout extends SingleChildLayoutDelegate {
  _AetherMenuLayout(this.position);

  final RelativeRect position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = position.left;
    var y = position.top;

    if (x + childSize.width > size.width - 8) {
      x = size.width - childSize.width - 8;
    }
    if (y + childSize.height > size.height - 8) {
      y = size.height - childSize.height - 8;
    }
    x = x.clamp(8.0, size.width - childSize.width - 8);
    y = y.clamp(8.0, size.height - childSize.height - 8);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _AetherMenuLayout oldDelegate) {
    return position != oldDelegate.position;
  }
}

class _AetherMenuPanel<T> extends StatelessWidget {
  const _AetherMenuPanel({
    required this.items,
    required this.minWidth,
    required this.maxWidth,
    required this.cfg,
    required this.onSelect,
  });

  final List<AetherMenuItem<T>> items;
  final double minWidth;
  final double maxWidth;
  final AppThemeConfig cfg;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
        ),
        child: AetherSurface(
          level: AetherSurfaceLevel.overlay,
          borderRadius: BorderRadius.circular(AetherRadius.md),
          padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  if (item.isDivider)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
                      child: Divider(height: 1, color: cfg.borderSubtle),
                    )
                  else
                    _AetherMenuRow<T>(
                      item: item,
                      cfg: cfg,
                      onSelect: onSelect,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AetherMenuRow<T> extends StatelessWidget {
  const _AetherMenuRow({
    required this.item,
    required this.cfg,
    required this.onSelect,
  });

  final AetherMenuItem<T> item;
  final AppThemeConfig cfg;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled
        ? cfg.textTertiary
        : item.destructive
            ? cfg.danger
            : item.warning
                ? cfg.warning
                : cfg.textPrimary;

    return AetherPressable(
      enabled: item.enabled && item.value != null,
      onTap: item.enabled && item.value != null
          ? () => onSelect(item.value as T)
          : null,
      borderRadius: BorderRadius.circular(AetherRadius.sm),
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: cfg.bgHover,
      pressedColor: cfg.pressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.lg,
          vertical: AetherSpace.sm,
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: AetherIconSize.md, color: color),
              const SizedBox(width: AetherSpace.md),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AetherType.bodyStyle(color).copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.shortcut != null) ...[
              const SizedBox(width: AetherSpace.lg),
              Text(
                item.shortcut!,
                style: AetherType.captionStyle(cfg.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

