import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/icon_size.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';

/// Styled dialog host. Enter: opacity + scale 0.96→1 (never from 0).
/// Exit is faster than enter ([AetherMotion.exitFactor]).
Future<T?> showAetherDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final cfg = context.tokens;
  final enter = AetherMotion.duration(context, AetherMotion.normal);
  final leave = AetherMotion.exitOf(context, AetherMotion.normal);
  final fromScale = AetherMotion.fromScale(context);

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _AetherDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: cfg.scrim,
      enterDuration: enter,
      exitDuration: leave,
      fromScale: fromScale,
      builder: builder,
    ),
  );
}

class _AetherDialogRoute<T> extends PopupRoute<T> {
  _AetherDialogRoute({
    required this.builder,
    required this.barrierDismissible,
    required this.barrierLabel,
    required this.barrierColor,
    required this.enterDuration,
    required this.exitDuration,
    required this.fromScale,
  });

  final WidgetBuilder builder;
  @override
  final bool barrierDismissible;
  @override
  final String barrierLabel;
  @override
  final Color barrierColor;
  final Duration enterDuration;
  final Duration exitDuration;
  final double fromScale;

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
    return builder(context);
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
        scale: Tween<double>(begin: fromScale, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class AetherDialog extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;
  final EdgeInsetsGeometry contentPadding;
  final bool showClose;

  const AetherDialog({
    super.key,
    this.title,
    this.titleWidget,
    required this.content,
    this.actions,
    this.maxWidth = 480,
    this.contentPadding = const EdgeInsets.fromLTRB(
      AetherSpace.xxl,
      AetherSpace.md,
      AetherSpace.xxl,
      AetherSpace.xxl,
    ),
    this.showClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: Colors.transparent,
          child: AetherSurface(
            level: AetherSurfaceLevel.overlay,
            borderRadius: BorderRadius.circular(AetherRadius.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null || titleWidget != null || showClose)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AetherSpace.xxl,
                        AetherSpace.xl,
                        AetherSpace.lg,
                        AetherSpace.xs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: titleWidget ??
                                Text(
                                  title ?? '',
                                  style: AetherType.titleStyle(cfg.textPrimary),
                                ),
                          ),
                          if (showClose)
                            AetherIconButton(
                              icon: Icons.close,
                              tooltip: '关闭',
                              size: 32,
                              iconSize: AetherIconSize.lg,
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
                            ),
                        ],
                      ),
                    ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: contentPadding,
                      child: content,
                    ),
                  ),
                  if (actions != null && actions!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AetherSpace.xl,
                        0,
                        AetherSpace.xl,
                        AetherSpace.xl,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (var i = 0; i < actions!.length; i++) ...[
                            if (i > 0) const SizedBox(width: AetherSpace.sm),
                            actions![i],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirm / destructive confirm helper.
Future<bool> showAetherConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool dangerous = false,
  bool doubleConfirm = false,
  String? doubleConfirmTitle,
  String? doubleConfirmMessage,
  String? doubleConfirmLabel,
}) async {
  Future<bool> once(
    String body, {
    required String actionLabel,
    String? dialogTitle,
  }) async {
    final result = await showAetherDialog<bool>(
      context: context,
      builder: (ctx) {
        final cfg = ctx.tokens;
        return AetherDialog(
          title: dialogTitle ?? title,
          content: Text(body, style: AetherType.bodyStyle(cfg.textSecondary)),
          actions: [
            AetherButton.ghost(
              label: cancelLabel,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            if (dangerous)
              AetherButton.danger(
                label: actionLabel,
                onPressed: () => Navigator.of(ctx).pop(true),
              )
            else
              AetherButton.primary(
                label: actionLabel,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
          ],
        );
      },
    );
    return result ?? false;
  }

  final first = await once(message, actionLabel: confirmLabel);
  if (!first) return false;
  if (!doubleConfirm) return true;
  if (!context.mounted) return false;
  return once(
    doubleConfirmMessage ?? message,
    actionLabel: doubleConfirmLabel ?? confirmLabel,
    dialogTitle: doubleConfirmTitle ?? title,
  );
}
