import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:flutter/widgets.dart';

/// Smooth discrete mouse wheel steps, while thumb and touch drags stay direct.
class SongTableScrollController extends ScrollController {
  bool smoothWheel = true;
  PointerDeviceKind pointerKind = PointerDeviceKind.mouse;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SongTableScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    smoothWheel: () => smoothWheel && pointerKind == PointerDeviceKind.mouse,
  );
}

class _SongTableScrollPosition extends ScrollPositionWithSingleContext {
  _SongTableScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.smoothWheel,
  });

  final bool Function() smoothWheel;

  @override
  void pointerScroll(double delta) {
    if (!smoothWheel() || delta == 0) {
      super.pointerScroll(delta);
      return;
    }
    final wheel = activity is _WheelScrollActivity
        ? activity! as _WheelScrollActivity
        : null;
    final pending = (wheel?.target ?? pixels) - pixels;
    final reverse = pending * delta < 0;
    final base = reverse ? pixels : (wheel?.target ?? pixels);
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) {
      if (wheel != null) goIdle();
      return;
    }
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
    if (wheel == null) {
      beginActivity(_WheelScrollActivity(this, context.vsync, target));
    } else if (target != wheel.target || reverse) {
      wheel.retarget(target, reverse: reverse);
    }
  }
}

/// A single ticker spans a wheel gesture. Retargeting preserves its velocity,
/// rather than restarting an ease-out (or its clock) for every wheel notch.
class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    ScrollPositionWithSingleContext super.position,
    TickerProvider vsync,
    this.target,
  ) : _from = position.pixels {
    // A small launch velocity makes the first notch respond on the next frame.
    _initialVelocity = (target - _from) / _settleSeconds * 2.6;
    _velocity = _initialVelocity;
    _segmentStart = -const Duration(milliseconds: 14);
    _ticker = vsync.createTicker(_tick)..start();
  }

  // Long enough to bridge normal wheel notches without stop/start pulses;
  // always finite so stopping input cannot leave a long ballistic tail.
  static const _settleSeconds = .17;
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration _segmentStart = Duration.zero;
  double _duration = _settleSeconds;
  double _from;
  double target;
  late double _initialVelocity;
  late double _velocity;
  bool _disposed = false;

  ScrollPositionWithSingleContext get _position =>
      delegate as ScrollPositionWithSingleContext;

  void retarget(double value, {bool reverse = false}) {
    _from = _position.pixels;
    target = value;
    _segmentStart = _elapsed;
    _duration = _settleSeconds;
    final distance = target - _from;
    // A direction change deliberately drops the previous destination and
    // velocity. Continuing that momentum would fight the user's wheel.
    _initialVelocity = reverse ? distance / _settleSeconds * 2.6 : _velocity;
    if (reverse) {
      _segmentStart = _elapsed - const Duration(milliseconds: 14);
    }
    if (_initialVelocity * distance > 0) {
      // Keep the cubic monotone even when dimensions shorten the destination.
      _duration = math.min(
        _duration,
        3 * distance.abs() / _initialVelocity.abs(),
      );
    }
    _velocity = _initialVelocity;
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final t = ((elapsed - _segmentStart).inMicroseconds / 1e6 / _duration)
        .clamp(0.0, 1.0);
    final distance = target - _from;
    final remaining = 1 - t;
    // Cubic Hermite: current position/velocity -> destination/zero velocity.
    // New input changes the destination without a position or speed jump.
    final pixels =
        _from +
        distance * t * t * (3 - 2 * t) +
        _initialVelocity * _duration * t * remaining * remaining;
    _velocity =
        distance / _duration * 6 * t * remaining +
        _initialVelocity * (1 - 4 * t + 3 * t * t);
    final overscroll = delegate.setPixels(pixels);
    if (!_disposed && (t == 1 || overscroll != 0)) delegate.goIdle();
  }

  @override
  void applyNewDimensions() {
    final position = _position;
    if (position.outOfRange) {
      delegate.goBallistic(0);
      return;
    }
    final bounded = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (bounded == position.pixels) {
      delegate.goIdle();
    } else if (bounded != target) {
      retarget(bounded);
    }
  }

  @override
  void resetActivity() => delegate.goBallistic(0);

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}
