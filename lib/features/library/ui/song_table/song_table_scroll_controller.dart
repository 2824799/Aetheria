import 'package:flutter/gestures.dart';
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
  double? _wheelTarget;
  bool _startingWheel = false;

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // A thumb/touch drag, a programmatic reveal, or an inertia cancellation
    // takes ownership immediately. Never resume a stale wheel destination.
    if (!_startingWheel) _wheelTarget = null;
    super.beginActivity(newActivity);
  }

  @override
  void pointerScroll(double delta) {
    if (!smoothWheel() || delta == 0) {
      super.pointerScroll(delta);
      return;
    }
    final pending = (_wheelTarget ?? pixels) - pixels;
    final base = pending * delta < 0 ? pixels : (_wheelTarget ?? pixels);
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    final remaining = target - pixels;
    if (remaining == 0) return;

    // Preserve the requested distance without letting fast wheel bursts leave
    // a long trailing chase. At most two rows remain in the eased portion.
    final immediate = remaining - remaining.clamp(-104.0, 104.0);
    if (immediate != 0) super.pointerScroll(immediate);
    _wheelTarget = target;
    _startingWheel = true;
    try {
      super.animateTo(
        target,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _startingWheel = false;
    }
  }
}
