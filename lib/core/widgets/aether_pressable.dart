import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';

/// Shared press + hover interaction shell.
///
/// - Short interruptible scale on press
/// - Optional hover/pressed background colors
/// - Honors reduced motion ([AetherMotion.reduce])
/// - No ink splash (theme uses [NoSplash])
class AetherPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool enabled;
  final bool enableHover;
  final double pressScale;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? pressedColor;
  final String? tooltip;
  final MouseCursor? cursor;

  const AetherPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.enableHover = true,
    this.pressScale = AetherMotion.pressScale,
    this.borderRadius,
    this.hoverColor,
    this.pressedColor,
    this.tooltip,
    this.cursor,
  });

  @override
  State<AetherPressable> createState() => _AetherPressableState();
}

class _AetherPressableState extends State<AetherPressable> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _canInteract =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onSecondaryTap != null);

  @override
  Widget build(BuildContext context) {
    final reduce = AetherMotion.reduce(context);
    final scale =
        (!reduce && _pressed && _canInteract) ? widget.pressScale : 1.0;

    Widget child = AnimatedScale(
      scale: scale,
      duration: AetherMotion.duration(context, AetherMotion.press),
      curve: AetherMotion.curve(context),
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.curve(context),
        decoration: BoxDecoration(
          color: _pressed && widget.pressedColor != null
              ? widget.pressedColor
              : (_hovered && widget.hoverColor != null
                  ? widget.hoverColor
                  : null),
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );

    child = MouseRegion(
      cursor: widget.cursor ??
          (_canInteract ? SystemMouseCursors.click : SystemMouseCursors.basic),
      onEnter: (_) {
        if (!widget.enableHover || !_canInteract) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!mounted) return;
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _canInteract ? widget.onTap : null,
        onLongPress: _canInteract ? widget.onLongPress : null,
        onSecondaryTap: _canInteract ? widget.onSecondaryTap : null,
        onTapDown: (_) {
          if (!_canInteract) return;
          setState(() => _pressed = true);
        },
        onTapUp: (_) {
          if (!mounted) return;
          setState(() => _pressed = false);
        },
        onTapCancel: () {
          if (!mounted) return;
          setState(() => _pressed = false);
        },
        child: child,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: child,
    );
  }
}
