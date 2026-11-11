import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/features/library/ui/song_table/song_columns.dart';

/// Order and widths of the song table columns, persisted across launches.
class SongTableColumnLayout extends ChangeNotifier {
  static const String _orderKey = 'aetheria-song-table-column-order';
  static const String _widthPrefix = 'aetheria-song-table-column-width-';
  static const double _maxWidth = 600;

  List<SongColumnKey> _order = List<SongColumnKey>.of(SongColumnKey.values);
  final Map<SongColumnKey, double> _widths = {
    for (final column in SongColumnKey.values) column: column.defaultWidth,
  };
  bool _disposed = false;

  List<SongColumnKey> get order => _order;

  double widthOf(SongColumnKey column) =>
      _widths[column] ?? column.defaultWidth;

  double get totalWidth =>
      _order.fold<double>(0, (sum, column) => sum + widthOf(column));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;

    final saved = prefs.getStringList(_orderKey) ?? const <String>[];
    final byName = {
      for (final column in SongColumnKey.values) column.name: column,
    };
    // Unknown names are dropped and columns added since the layout was saved
    // are appended, so an old preference can never hide a column.
    final resolved = <SongColumnKey>{
      for (final name in saved) ?byName[name],
      ...SongColumnKey.values,
    };
    _order = resolved.toList();

    for (final column in SongColumnKey.values) {
      final stored = prefs.getDouble('$_widthPrefix${column.name}');
      if (stored != null) {
        _widths[column] = _clamp(column, stored);
      }
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, [
      for (final column in _order) column.name,
    ]);
    for (final entry in _widths.entries) {
      await prefs.setDouble('$_widthPrefix${entry.key.name}', entry.value);
    }
  }

  void resize(SongColumnKey column, double delta) {
    final next = _clamp(column, widthOf(column) + delta);
    if (next == widthOf(column)) return;
    _widths[column] = next;
    notifyListeners();
  }

  /// Moves [dragged] to the position currently held by [target].
  void reorder(SongColumnKey dragged, SongColumnKey target) {
    final from = _order.indexOf(dragged);
    final to = _order.indexOf(target);
    if (from == to || from < 0 || to < 0) return;
    _order = List<SongColumnKey>.of(_order)
      ..removeAt(from)
      ..insert(to, dragged);
    notifyListeners();
    save();
  }

  double _clamp(SongColumnKey column, double width) =>
      width.clamp(column.minWidth, _maxWidth).toDouble();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
