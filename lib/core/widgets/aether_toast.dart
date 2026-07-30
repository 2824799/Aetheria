import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';

enum AetherToastKind { info, success, warning, error }

OverlayEntry? _activeToastEntry;

/// Lightweight toast with same-direction enter/exit.
///
/// Replaces [SnackBar] so timing, motion, and chrome stay on the design system.
void showAetherToast(
  BuildContext context, {
  required String message,
  AetherToastKind kind = AetherToastKind.info,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final cfg = context.tokens;
  final Color accent;
  switch (kind) {
    case AetherToastKind.info:
      accent = cfg.info;
    case AetherToastKind.success:
      accent = cfg.success;
    case AetherToastKind.warning:
      accent = cfg.warning;
    case AetherToastKind.error:
      accent = cfg.danger;
  }

  _activeToastEntry?.remove();
  _activeToastEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return _AetherToastHost(
        message: message,
        accent: accent,
        cfg: cfg,
        duration: duration,
        onDone: () {
          entry.remove();
          if (identical(_activeToastEntry, entry)) {
            _activeToastEntry = null;
          }
        },
      );
    },
  );

  _activeToastEntry = entry;
  overlay.insert(entry);
}

class _AetherToastHost extends StatefulWidget {
  final String message;
  final Color accent;
  final AppThemeConfig cfg;
  final Duration duration;
  final VoidCallback onDone;

  const _AetherToastHost({
    required this.message,
    required this.accent,
    required this.cfg,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_AetherToastHost> createState() => _AetherToastHostState();
}

class _AetherToastHostState extends State<_AetherToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AetherMotion.normal,
      reverseDuration: AetherMotion.exit(AetherMotion.normal),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: AetherMotion.out,
      reverseCurve: AetherMotion.out,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AetherMotion.out,
        reverseCurve: AetherMotion.out,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      _hold = Timer(widget.duration, _dismiss);
    });
  }

  Future<void> _dismiss() async {
    _hold?.cancel();
    if (!mounted) {
      widget.onDone();
      return;
    }
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      widget.onDone();
      return;
    }
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + AetherSpace.huge;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AetherSpace.xl,
            0,
            AetherSpace.xl,
            bottom,
          ),
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _offset,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.cfg.bgPopover,
                      borderRadius: BorderRadius.circular(AetherRadius.md),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: widget.cfg.brightness == Brightness.dark
                                ? 0.35
                                : 0.12,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AetherSpace.xl,
                        vertical: AetherSpace.lg,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AetherSpace.lg - 2),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: AetherType.bodyStyle(
                                widget.cfg.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
