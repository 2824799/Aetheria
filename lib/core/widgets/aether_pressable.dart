import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';

/// Shared press + hover + focus interaction shell.
///
/// - Short interruptible scale on press
/// - Hover only on fine pointers (mouse / trackpad)
/// - Optional focus ring via [showFocus] / Focus traversal
/// - Honors reduced motion ([AetherMotion.reduce])
/// - No ink splash (theme uses [NoSplash])
class AetherPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool enabled;
  final bool enableHover;
  final bool showFocus;
  final double pressScale;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? pressedColor;
  final String? tooltip;
  final String? semanticLabel;
  final MouseCursor? cursor;

  const AetherPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.enableHover = true,
    this.showFocus = true,
    this.pressScale = AetherMotion.pressScale,
    this.borderRadius,
    this.hoverColor,
    this.pressedColor,
    this.tooltip,
    this.semanticLabel,
    this.cursor,
  });

  @override
  State<AetherPressable> createState() => _AetherPressableState();
}

class _AetherPressableState extends State<AetherPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool _finePointer = false;

  bool get _canInteract =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onSecondaryTap != null);

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final reduce = AetherMotion.reduce(context);
    final scale =
        (!reduce && _pressed && _canInteract) ? widget.pressScale : 1.0;
    final radius = widget.borderRadius ?? BorderRadius.circular(AetherRadius.md);
    final showHover =
        widget.enableHover && _finePointer && _hovered && widget.hoverColor != null;
    final showFocusRing = widget.showFocus && _focused && _canInteract;

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
              : (showHover ? widget.hoverColor : null),
          borderRadius: radius,
          border: showFocusRing
              ? Border.all(color: cfg.borderFocus, width: 1.5)
              : null,
        ),
        child: widget.child,
      ),
    );

    child = FocusableActionDetector(
      enabled: _canInteract,
      onShowFocusHighlight: (value) {
        if (_focused == value) return;
        setState(() => _focused = value);
      },
      onShowHoverHighlight: (_) {},
      shortcuts: widget.onTap == null
          ? null
          : const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
      actions: widget.onTap == null
          ? null
          : <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onTap?.call();
                  return null;
                },
              ),
            },
      child: MouseRegion(
        cursor: widget.cursor ??
            (_canInteract ? SystemMouseCursors.click : SystemMouseCursors.basic),
        onEnter: (event) {
          final fine = event.kind == PointerDeviceKind.mouse ||
              event.kind == PointerDeviceKind.trackpad;
          if (_finePointer != fine) {
            setState(() => _finePointer = fine);
          }
          if (!widget.enableHover || !_canInteract || !fine) return;
          _setHovered(true);
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
          onTapDown: (details) {
            if (!_canInteract) return;
            final fine = details.kind == PointerDeviceKind.mouse ||
                details.kind == PointerDeviceKind.trackpad;
            if (_finePointer != fine) {
              setState(() {
                _finePointer = fine;
                _pressed = true;
              });
            } else {
              _setPressed(true);
            }
          },
          onTapUp: (_) {
            if (!mounted) return;
            _setPressed(false);
          },
          onTapCancel: () {
            if (!mounted) return;
            _setPressed(false);
          },
          child: child,
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }

    if (widget.semanticLabel != null && widget.semanticLabel!.isNotEmpty) {
      child = Semantics(
        button: _canInteract,
        enabled: widget.enabled,
        label: widget.semanticLabel,
        child: child,
      );
    }

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: child,
    );
  }
}
