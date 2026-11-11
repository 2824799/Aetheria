import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Row selection for the song table: click, ctrl/shift click and marquee.
///
/// Selection changes are published through [changes] and the marquee through
/// [marquee], so pointer motion repaints without rebuilding the table.
class SongTableSelection {
  static const double _dragThreshold = 6;

  final Set<String> _ids = <String>{};
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> marquee = ValueNotifier<Rect?>(null);

  int _anchorIndex = -1;
  Offset? _origin;
  Set<String> _idsBeforeMarquee = const <String>{};
  bool _additive = false;
  bool _dragging = false;
  int _marqueeFirst = -1;
  int _marqueeLast = -1;

  /// True from the moment a press turns into a marquee until the next press,
  /// so the release that ends a drag is not also handled as a row click.
  bool suppressRowTap = false;

  bool contains(String songId) => _ids.contains(songId);

  List<String> get ids => List<String>.of(_ids);

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    changes.value++;
  }

  void selectOnly(String songId, int index) {
    _ids
      ..clear()
      ..add(songId);
    _anchorIndex = index;
    changes.value++;
  }

  void click(
    Song song,
    int index,
    List<Song> songs, {
    required bool toggle,
    required bool range,
  }) {
    if (toggle) {
      if (!_ids.remove(song.id)) {
        _ids.add(song.id);
      }
      _anchorIndex = index;
    } else if (range && _anchorIndex >= 0 && _anchorIndex < songs.length) {
      final start = math.min(index, _anchorIndex);
      final end = math.max(index, _anchorIndex);
      _ids
        ..clear()
        ..addAll(songs.sublist(start, end + 1).map((item) => item.id));
    } else {
      _ids
        ..clear()
        ..add(song.id);
      _anchorIndex = index;
    }
    changes.value++;
  }

  void pressDown(Offset position, {required bool additive}) {
    suppressRowTap = false;
    _origin = position;
    _additive = additive;
    _idsBeforeMarquee = additive ? Set<String>.of(_ids) : const <String>{};
    _dragging = false;
    _marqueeFirst = -1;
    _marqueeLast = -1;
  }

  void pressMove(
    Offset position,
    List<Song> songs, {
    required double scrollOffset,
    required double rowHeight,
  }) {
    final origin = _origin;
    if (origin == null) return;
    if (!_dragging && (position - origin).distance < _dragThreshold) return;

    _dragging = true;
    suppressRowTap = true;
    marquee.value = Rect.fromPoints(origin, position);
    if (songs.isEmpty) return;

    final top = math.min(origin.dy, position.dy) + scrollOffset;
    final bottom = math.max(origin.dy, position.dy) + scrollOffset;
    final first = (top / rowHeight).floor().clamp(0, songs.length - 1);
    final last = (bottom / rowHeight).floor().clamp(0, songs.length - 1);
    if (first == _marqueeFirst && last == _marqueeLast) return;
    _marqueeFirst = first;
    _marqueeLast = last;

    _ids
      ..clear()
      ..addAll(_additive ? _idsBeforeMarquee : const <String>{})
      ..addAll(songs.sublist(first, last + 1).map((song) => song.id));
    _anchorIndex = last;
    changes.value++;
  }

  void pressEnd() {
    marquee.value = null;
    _origin = null;
    _idsBeforeMarquee = const <String>{};
    _additive = false;
    _dragging = false;
  }

  void dispose() {
    changes.dispose();
    marquee.dispose();
  }
}

/// Paints the marquee rectangle; repaints on pointer motion only.
class SongTableMarqueePainter extends CustomPainter {
  SongTableMarqueePainter(this.rect, this.color) : super(repaint: rect);

  final ValueNotifier<Rect?> rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = rect.value;
    if (bounds == null) return;
    final rounded = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(AetherRadius.sm),
    );
    canvas.drawRRect(rounded, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant SongTableMarqueePainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}
