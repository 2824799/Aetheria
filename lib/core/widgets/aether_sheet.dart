import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';

/// Bottom sheet host with enter/exit motion tokens.
///
/// Set [decorate] to false when the child provides its own chrome
/// (full-bleed detail sheets, custom gradients, etc.).
Future<T?> showAetherSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool decorate = true,
  double? maxHeightFactor,
}) {
  final cfg = context.tokens;
  final enter = AetherMotion.duration(context, AetherMotion.panel);
  final leave = AetherMotion.exitOf(context, AetherMotion.panel);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: cfg.scrim,
    sheetAnimationStyle: AnimationStyle(
      duration: enter,
      reverseDuration: leave,
      curve: AetherMotion.curve(context, AetherMotion.outQuart),
      reverseCurve: AetherMotion.curve(context, AetherMotion.out),
    ),
    builder: (context) {
      final factor = maxHeightFactor ?? (decorate ? 0.92 : 0.95);
      final maxHeight = MediaQuery.sizeOf(context).height * factor;
      final child = builder(context);
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: decorate ? AetherSheet(child: child) : child,
          ),
        ),
      );
    },
  );
}

class AetherSheet extends StatelessWidget {
  final Widget child;
  final bool showGrabber;

  const AetherSheet({
    super.key,
    required this.child,
    this.showGrabber = true,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return AetherSurface(
      level: AetherSurfaceLevel.overlay,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AetherRadius.xxl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showGrabber) ...[
            const SizedBox(height: AetherSpace.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cfg.borderStrong,
                borderRadius: BorderRadius.circular(AetherRadius.full),
              ),
            ),
            const SizedBox(height: AetherSpace.sm),
          ],
          child,
        ],
      ),
    );
  }
}
