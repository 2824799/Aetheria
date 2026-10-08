import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/gestures.dart' show kPrimaryButton, computeHitSlop;
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
  final GestureLongPressStartCallback? onLongPressStart;
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
    this.onLongPressStart,
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
  int? _pressedPointer;
  Offset? _pressOrigin;
  bool _pressPainted = false;
  bool _releasePending = false;
  int _pressEpoch = 0;

  bool get _canInteract =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onLongPressStart != null ||
          widget.onSecondaryTap != null);

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    final epoch = ++_pressEpoch;
    _releasePending = false;
    setState(() => _pressed = value);
    if (value) {
      _pressPainted = false;
      // A fast down/up can arrive between frames. Show one pressed frame,
      // without delaying the action, before starting the release animation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _pressEpoch) return;
        _pressPainted = true;
        if (_releasePending) _setPressed(false);
      });
    }
  }

  void _releasePressed() {
    if (_pressed && !_pressPainted) {
      _releasePending = true;
    } else {
      _setPressed(false);
    }
  }

  @override
  void didUpdateWidget(covariant AetherPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canInteract) {
      _pressed = false;
      _hovered = false;
      _pressedPointer = null;
      _pressEpoch++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final reduce = AetherMotion.reduce(context);
    final scale = (!reduce && _pressed && _canInteract)
        ? widget.pressScale
        : 1.0;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AetherRadius.md);
    final showHover =
        widget.enableHover &&
        _finePointer &&
        _hovered &&
        widget.hoverColor != null;
    final showFocusRing = widget.showFocus && _focused && _canInteract;

    Widget child = AnimatedScale(
      scale: scale,
      duration: _pressed
          ? Duration.zero
          : AetherMotion.duration(context, AetherMotion.press),
      curve: AetherMotion.curve(context),
      child: Container(
        foregroundDecoration: BoxDecoration(
          color: _pressed
              ? (widget.pressedColor ?? cfg.pressed)
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
                  if (_canInteract) widget.onTap?.call();
                  return null;
                },
              ),
            },
      child: MouseRegion(
        cursor:
            widget.cursor ??
            (_canInteract
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic),
        onEnter: (event) {
          final fine =
              event.kind == PointerDeviceKind.mouse ||
              event.kind == PointerDeviceKind.trackpad;
          if (_finePointer != fine) {
            _finePointer = fine;
          }
          if (!widget.enableHover || !_canInteract || !fine) return;
          _setHovered(true);
        },
        onExit: (_) {
          if (!mounted) return;
          if (_hovered || _pressed) {
            setState(() {
              _hovered = false;
              _pressed = false;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _canInteract ? widget.onTap : null,
          onLongPress: _canInteract ? widget.onLongPress : null,
          onLongPressStart: _canInteract ? widget.onLongPressStart : null,
          onSecondaryTap: _canInteract ? widget.onSecondaryTap : null,
          onTapUp: (_) {
            if (!mounted) return;
            _releasePressed();
          },
          onTapCancel: () {
            if (!mounted) return;
            _setPressed(false);
          },
          child: Listener(
            onPointerDown: (event) {
              if (!_canInteract ||
                  event.buttons != kPrimaryButton ||
                  _pressedPointer != null) {
                return;
              }
              _pressedPointer = event.pointer;
              _pressOrigin = event.position;
              _setPressed(true);
            },
            onPointerMove: (event) {
              if (event.pointer == _pressedPointer &&
                  _pressed &&
                  (event.position - _pressOrigin!).distance >
                      computeHitSlop(event.kind, null)) {
                _setPressed(false);
              }
            },
            onPointerUp: (event) {
              if (event.pointer != _pressedPointer) return;
              _pressedPointer = null;
              _releasePressed();
            },
            onPointerCancel: (event) {
              if (event.pointer != _pressedPointer) return;
              _pressedPointer = null;
              _setPressed(false);
            },
            child: child,
          ),
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

    return Opacity(opacity: widget.enabled ? 1 : 0.45, child: child);
  }
}
