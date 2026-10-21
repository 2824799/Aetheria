import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:flutter/widgets.dart';

/// One fixed vertical track for a table whose content also scrolls horizontally.
/// Its top padding excludes the header, and its track extent spans down to the
/// table's bottom edge without leaving an artificial header-sized gap.
class SongTableScrollbar extends RawScrollbar {
  SongTableScrollbar({
    super.key,
    required super.controller,
    required super.child,
    required super.thumbColor,
    required this.headerHeight,
    required this.onDraggingChanged,
  }) : super(
         thumbVisibility: true,
         interactive: true,
         thickness: 8,
         radius: const Radius.circular(AetherRadius.xs),
         padding: EdgeInsets.only(top: headerHeight),
         notificationPredicate: _verticalNotification,
       );

  final double headerHeight;
  final ValueChanged<bool> onDraggingChanged;

  static bool _verticalNotification(ScrollNotification notification) =>
      notification.metrics.axis == Axis.vertical && notification.depth == 1;

  @override
  RawScrollbarState<SongTableScrollbar> createState() =>
      _SongTableScrollbarState();
}

class _SongTableScrollbarState extends RawScrollbarState<SongTableScrollbar> {
  @override
  void handleThumbPressStart(Offset localPosition) {
    widget.onDraggingChanged(true);
    super.handleThumbPressStart(localPosition);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    widget.onDraggingChanged(false);
  }

  void _applyAdjustedMetrics(ScrollMetrics m) {
    final adjusted = FixedScrollMetrics(
      minScrollExtent: m.minScrollExtent,
      maxScrollExtent: m.maxScrollExtent,
      pixels: m.pixels,
      viewportDimension: m.viewportDimension + widget.headerHeight,
      axisDirection: m.axisDirection,
      devicePixelRatio: m.devicePixelRatio,
    );
    scrollbarPainter.update(adjusted, m.axisDirection);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical && notification.depth == 1) {
      _applyAdjustedMetrics(notification.metrics);
    }
    return false;
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.metrics.axis == Axis.vertical && notification.depth == 1) {
      _applyAdjustedMetrics(notification.metrics);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: super.build(context),
      ),
    );
  }
}
