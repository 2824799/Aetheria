import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:flutter/widgets.dart';

/// One fixed vertical track for a table whose content also scrolls horizontally.
/// Its top padding excludes the header, and nested horizontal notifications
/// cannot replace the vertical thumb's metrics.
class SongTableScrollbar extends RawScrollbar {
  SongTableScrollbar({
    super.key,
    required super.controller,
    required super.child,
    required super.thumbColor,
    required double headerHeight,
    required this.onDraggingChanged,
  }) : super(
         thumbVisibility: true,
         interactive: true,
         thickness: 8,
         radius: const Radius.circular(AetherRadius.xs),
         padding: EdgeInsets.only(top: headerHeight),
         notificationPredicate: _verticalNotification,
       );

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
}
