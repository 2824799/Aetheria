import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';

enum _SongColumnKey { title, artist, tags, versions, spec }

extension on _SongColumnKey {
  String get label => switch (this) {
        _SongColumnKey.title => '歌曲名称',
        _SongColumnKey.artist => '歌手',
        _SongColumnKey.tags => '标签',
        _SongColumnKey.versions => '版本数',
        _SongColumnKey.spec => '默认音质',
      };

  double get defaultWidth => switch (this) {
        _SongColumnKey.title => 280,
        _SongColumnKey.artist => 200,
        _SongColumnKey.tags => 240,
        _SongColumnKey.versions => 92,
        _SongColumnKey.spec => 170,
      };

  double get minWidth => switch (this) {
        _SongColumnKey.title => 180,
        _SongColumnKey.artist => 140,
        _SongColumnKey.tags => 160,
        _SongColumnKey.versions => 76,
        _SongColumnKey.spec => 140,
      };
}

class SongTable extends StatefulWidget {
  const SongTable({super.key});

  @override
  State<SongTable> createState() => _SongTableState();
}

class _SongTableState extends State<SongTable> {
  static const double _headerHeight = 46;
  static const double _rowHeight = 52;
  static const double _leadingColumnWidth = 52;
  static const double _dragThreshold = 6;
  static const String _columnOrderKey = 'aetheria-song-table-column-order';
  static const String _columnWidthPrefix =
      'aetheria-song-table-column-width-';

  final ScrollController _verticalController = ScrollController();
  final Set<String> _selectedSongIds = <String>{};
  final Map<_SongColumnKey, double> _columnWidths = {
    for (final column in _SongColumnKey.values) column: column.defaultWidth,
  };

  List<_SongColumnKey> _columnOrder = List<_SongColumnKey>.from(
    _SongColumnKey.values,
  );
  int _lastSelectedIndex = -1;
  Offset? _selectionOrigin;
  Offset? _selectionCurrent;
  Set<String> _selectionBaseIds = <String>{};
  bool _isBoxSelecting = false;
  bool _isPointerDownForSelection = false;
  bool _boxSelectionAdditive = false;
  DateTime? _lastPrimaryTapAt;
  String? _lastPrimaryTapSongId;

  @override
  void initState() {
    super.initState();
    _loadColumnLayout();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _loadColumnLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_columnOrderKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      final resolved = <_SongColumnKey>[];
      for (final name in savedOrder) {
        for (final column in _SongColumnKey.values) {
          if (column.name == name && !resolved.contains(column)) {
            resolved.add(column);
            break;
          }
        }
      }
      for (final column in _SongColumnKey.values) {
        if (!resolved.contains(column)) {
          resolved.add(column);
        }
      }
      _columnOrder = resolved;
    }

    for (final column in _SongColumnKey.values) {
      final stored = prefs.getDouble('$_columnWidthPrefix${column.name}');
      if (stored != null) {
        _columnWidths[column] = stored.clamp(column.minWidth, 600).toDouble();
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveColumnLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _columnOrderKey,
      _columnOrder.map((column) => column.name).toList(),
    );
    for (final entry in _columnWidths.entries) {
      await prefs.setDouble(
        '$_columnWidthPrefix${entry.key.name}',
        entry.value,
      );
    }
  }

  bool _isMultiSelectModifierPressed() {
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  void _handleRowClick(
    Song song,
    int index,
    bool isCtrlPressed,
    bool isShiftPressed,
    List<Song> songs,
  ) {
    setState(() {
      if (isCtrlPressed) {
        if (_selectedSongIds.contains(song.id)) {
          _selectedSongIds.remove(song.id);
        } else {
          _selectedSongIds.add(song.id);
        }
        _lastSelectedIndex = index;
        return;
      }

      if (isShiftPressed && _lastSelectedIndex != -1) {
        final start = math.min(index, _lastSelectedIndex);
        final end = math.max(index, _lastSelectedIndex);
        _selectedSongIds
          ..clear()
          ..addAll(songs.sublist(start, end + 1).map((item) => item.id));
        return;
      }

      _selectedSongIds
        ..clear()
        ..add(song.id);
      _lastSelectedIndex = index;
    });
  }

  Future<void> _handleRowPrimaryTap(
    Song song,
    int index,
    List<Song> songs,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
  ) async {
    final isCtrlPressed = _isMultiSelectModifierPressed();
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    _handleRowClick(song, index, isCtrlPressed, isShiftPressed, songs);

    if (isCtrlPressed || isShiftPressed) {
      _lastPrimaryTapAt = null;
      _lastPrimaryTapSongId = null;
      return;
    }

    audioProvider.setActiveSong(song);
    audioProvider.setDetailOpen(true);

    final now = DateTime.now();
    final isDoubleTap =
        _lastPrimaryTapSongId == song.id &&
        _lastPrimaryTapAt != null &&
        now.difference(_lastPrimaryTapAt!) <
            const Duration(milliseconds: 260);

    _lastPrimaryTapSongId = song.id;
    _lastPrimaryTapAt = now;

    if (!isDoubleTap) {
      return;
    }

    try {
      await audioProvider.playSong(
        song,
        songs,
        libraryProvider.libraryPath,
        audioServerPort: libraryProvider.audioServerPort,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
    Song song,
    LibraryProvider provider,
  ) async {
    final isRowAlreadySelected = _selectedSongIds.contains(song.id);
    if (!isRowAlreadySelected) {
      setState(() {
        _selectedSongIds
          ..clear()
          ..add(song.id);
        _lastSelectedIndex = provider.displaySongs.indexWhere(
          (entry) => entry.id == song.id,
        );
      });
    }

    final targetSongIds = isRowAlreadySelected
        ? List<String>.from(_selectedSongIds)
        : <String>[song.id];
    final cfg = context.read<UIThemeProvider>().currentTheme;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.of(context).size.width - position.dx,
        MediaQuery.of(context).size.height - position.dy,
      ),
      color: cfg.bgPanel.withOpacity(0.98),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withOpacity(0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cfg.border.withOpacity(0.9)),
      ),
      items: _buildContextMenuItems(provider, cfg),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.startsWith('playlist:')) {
      final playlistId = result.substring('playlist:'.length);
      Playlist? playlist;
      for (final entry in provider.playlists) {
        if (entry.id == playlistId) {
          playlist = entry;
          break;
        }
      }
      if (playlist == null) {
        return;
      }
      try {
        await provider.addSongsToPlaylist(playlist.id, targetSongIds);
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已成功添加至歌单: ${playlist.name}')));
      } catch (e) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('添加失败: $e')));
      }
      return;
    }

    await _handleCommand(result, targetSongIds, provider);
  }

  List<PopupMenuEntry<String>> _buildContextMenuItems(
    LibraryProvider provider,
    AppThemeConfig cfg,
  ) {
    final items = <PopupMenuEntry<String>>[
      _menuItem('copy', Icons.copy, '复制所选歌曲', cfg),
      _menuItem('cut', Icons.content_cut, '剪切所选歌曲', cfg),
      _menuItem(
        'delete',
        Icons.delete_forever,
        '彻底删除歌曲',
        cfg,
        color: Colors.redAccent,
      ),
    ];

    if (provider.activePlaylistId != null) {
      items.add(
        _menuItem(
          'remove_playlist',
          Icons.playlist_remove,
          '从当前歌单移除',
          cfg,
          color: Colors.orangeAccent,
        ),
      );
    }

    if (provider.playlists.isNotEmpty) {
      items.add(const PopupMenuDivider(height: 8));
      for (final playlist in provider.playlists) {
        items.add(
          _menuItem(
            'playlist:${playlist.id}',
            Icons.playlist_add,
            '添加到歌单 · ${playlist.name}',
            cfg,
          ),
        );
      }
    }

    final clipboardCount = provider.clipboard == null
        ? null
        : (provider.clipboard!['songIds'] as List).length;
    if (provider.activePlaylistId != null && clipboardCount != null) {
      items.add(const PopupMenuDivider(height: 8));
      items.add(
        _menuItem(
          'paste',
          Icons.paste,
          '粘贴歌曲 ($clipboardCount 首)',
          cfg,
        ),
      );
    }

    return items;
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    AppThemeConfig cfg, {
    Color? color,
  }) {
    final foreground = color ?? cfg.textMain;
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: foreground.withOpacity(0.95)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCommand(
    String cmd,
    List<String> targetSongIds,
    LibraryProvider provider,
  ) async {
    final activePlaylistId = provider.activePlaylistId;
    if (cmd == 'copy') {
      provider.setClipboard('copy', targetSongIds, activePlaylistId);
      return;
    }
    if (cmd == 'cut') {
      provider.setClipboard('cut', targetSongIds, activePlaylistId);
      return;
    }
    if (cmd == 'delete') {
      _confirmDeleteSongs(context, targetSongIds, provider);
      return;
    }
    if (cmd == 'remove_playlist' && activePlaylistId != null) {
      await provider.removeSongsFromPlaylist(activePlaylistId, targetSongIds);
      return;
    }
    if (cmd == 'paste' && activePlaylistId != null) {
      await provider.pasteSongs(activePlaylistId);
    }
  }

  void _confirmDeleteSongs(
    BuildContext context,
    List<String> songIds,
    LibraryProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除歌曲？'),
        content: Text(
          '您确定要将这 ${songIds.length} 首歌曲从音乐库彻底删除吗？这会同时删除本地物理音频文件！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                for (final id in songIds) {
                  await provider.deleteSong(id);
                }
                if (!mounted) {
                  return;
                }
                setState(() {
                  _selectedSongIds.clear();
                });
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('删除歌曲成功')));
              } catch (e) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _isPointerDownForSelection = true;
    _selectionOrigin = event.localPosition;
    _selectionCurrent = event.localPosition;
    _selectionBaseIds = _isMultiSelectModifierPressed()
        ? Set<String>.from(_selectedSongIds)
        : <String>{};
    _boxSelectionAdditive = _isMultiSelectModifierPressed();
    _isBoxSelecting = false;
  }

  void _handlePointerMove(PointerMoveEvent event, List<Song> songs) {
    if (!_isPointerDownForSelection || _selectionOrigin == null) {
      return;
    }

    final movedDistance = (event.localPosition - _selectionOrigin!).distance;
    if (!_isBoxSelecting && movedDistance < _dragThreshold) {
      return;
    }

    if (!_isBoxSelecting) {
      setState(() {
        _isBoxSelecting = true;
      });
    }

    setState(() {
      _selectionCurrent = event.localPosition;
      _selectSongsInRect(songs);
    });
  }

  void _handlePointerUp() {
    if (!_isPointerDownForSelection) {
      return;
    }
    setState(() {
      _isPointerDownForSelection = false;
      _selectionOrigin = null;
      _selectionCurrent = null;
      _selectionBaseIds = <String>{};
      _boxSelectionAdditive = false;
      _isBoxSelecting = false;
    });
  }

  void _selectSongsInRect(List<Song> songs) {
    final origin = _selectionOrigin;
    final current = _selectionCurrent;
    if (origin == null || current == null || songs.isEmpty) {
      return;
    }

    final top = math.min(origin.dy, current.dy) + _verticalController.offset;
    final bottom = math.max(origin.dy, current.dy) + _verticalController.offset;
    final firstIndex = (top / _rowHeight).floor().clamp(0, songs.length - 1);
    final lastIndex = (bottom / _rowHeight).floor().clamp(0, songs.length - 1);

    final selectedInRect = songs
        .sublist(firstIndex, lastIndex + 1)
        .map((song) => song.id)
        .toSet();

    _selectedSongIds
      ..clear()
      ..addAll(_boxSelectionAdditive ? _selectionBaseIds : const <String>{})
      ..addAll(selectedInRect);
    _lastSelectedIndex = lastIndex;
  }

  void _resizeColumn(_SongColumnKey column, double delta) {
    final nextWidth = (_columnWidths[column] ?? column.defaultWidth) + delta;
    setState(() {
      _columnWidths[column] = nextWidth.clamp(column.minWidth, 600).toDouble();
    });
    _saveColumnLayout();
  }

  void _reorderColumn(_SongColumnKey dragged, _SongColumnKey target) {
    if (dragged == target) {
      return;
    }
    final currentOrder = List<_SongColumnKey>.from(_columnOrder);
    final from = currentOrder.indexOf(dragged);
    final to = currentOrder.indexOf(target);
    if (from == -1 || to == -1) {
      return;
    }

    currentOrder.removeAt(from);
    currentOrder.insert(to, dragged);

    setState(() {
      _columnOrder = currentOrder;
    });
    _saveColumnLayout();
  }

  double _tableWidth(double availableWidth) {
    final contentWidth = _leadingColumnWidth +
        _columnOrder.fold<double>(
          0,
          (sum, column) => sum + (_columnWidths[column] ?? column.defaultWidth),
        );
    return math.max(availableWidth, contentWidth);
  }

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  AudioVersion? _primaryVersionFor(Song song) {
    for (final version in song.versions) {
      if (version.isPrimary) {
        return version;
      }
    }
    if (song.versions.isNotEmpty) {
      return song.versions.first;
    }
    return null;
  }

  Widget _buildHeaderCell(_SongColumnKey column, AppThemeConfig cfg) {
    final width = _columnWidths[column] ?? column.defaultWidth;
    return SizedBox(
      width: width,
      height: _headerHeight,
      child: DragTarget<_SongColumnKey>(
        onWillAcceptWithDetails: (details) => details.data != column,
        onAcceptWithDetails: (details) =>
            _reorderColumn(details.data, column),
        builder: (context, candidateData, rejectedData) {
          final isDropTarget = candidateData.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: isDropTarget
                  ? cfg.bgHover.withOpacity(0.08)
                  : Colors.transparent,
              border: Border(
                right: BorderSide(color: cfg.border.withOpacity(0.45)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Draggable<_SongColumnKey>(
                    data: column,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: width,
                        height: _headerHeight - 8,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cfg.bgPanel.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cfg.accent.withOpacity(0.55)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.22),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          column.label,
                          style: TextStyle(
                            color: cfg.textMain,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: _buildHeaderLabel(column, cfg),
                    ),
                    child: _buildHeaderLabel(column, cfg),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) =>
                        _resizeColumn(column, details.delta.dx),
                    child: Container(
                      width: 12,
                      alignment: Alignment.center,
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: cfg.border.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderLabel(_SongColumnKey column, AppThemeConfig cfg) {
    final centered = column == _SongColumnKey.versions || column == _SongColumnKey.spec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Text(
        column.label,
        textAlign: centered ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          color: cfg.textSub,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildCell(
    _SongColumnKey column,
    Song song,
    AudioVersion? primaryVersion,
    AppThemeConfig cfg,
    bool isCurrentlyPlaying,
  ) {
    final width = _columnWidths[column] ?? column.defaultWidth;

    switch (column) {
      case _SongColumnKey.title:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrentlyPlaying ? cfg.accent : cfg.textMain,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        );
      case _SongColumnKey.artist:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              song.artist ?? '未知歌手',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cfg.textSub,
                fontSize: 12,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        );
      case _SongColumnKey.tags:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: song.tags.isEmpty
                ? Text(
                    '无标签',
                    style: TextStyle(
                      color: cfg.textSub.withOpacity(0.75),
                      fontSize: 11,
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: song.tags.map((tag) {
                        final tagColor = tag.color != null
                            ? _parseHexColor(tag.color!, cfg.accent)
                            : cfg.accent;
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tagColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                            border: Border(
                              left: BorderSide(color: tagColor, width: 2),
                            ),
                          ),
                          child: Text(
                            tag.name,
                            style: TextStyle(
                              fontSize: 10,
                              color: tagColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        );
      case _SongColumnKey.versions:
        return SizedBox(
          width: width,
          child: Center(
            child: Text(
              song.versions.length.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cfg.textMain,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      case _SongColumnKey.spec:
        var specText = '未知';
        var formatText = '';
        if (primaryVersion != null) {
          final frequency = primaryVersion.sampleRate != null
              ? '${(primaryVersion.sampleRate! / 1000).toStringAsFixed(1).replaceAll('.0', '')}k'
              : '';
          final bitDepth =
              (primaryVersion.format?.toLowerCase() == 'flac' &&
                      primaryVersion.bitDepth != null)
                  ? '${primaryVersion.bitDepth}b'
                  : '';
          final bitrate = primaryVersion.bitrate != null
              ? '${(primaryVersion.bitrate! / 1000).round()}kbps'
              : '';
          final loudness = primaryVersion.loudness != null
              ? '${primaryVersion.loudness!.toStringAsFixed(1)}dB'
              : '';
          specText = [frequency, bitDepth, bitrate, loudness]
              .where((item) => item.isNotEmpty)
              .join('/');
          if (specText.isEmpty) {
            specText = '未知';
          }
          formatText = primaryVersion.format ?? '';
        }

        final badgeColor = switch (formatText.toLowerCase()) {
          'flac' => const Color(0xFF10B981),
          'wav' => Colors.blue,
          _ => cfg.textSub,
        };
        final badgeBg = switch (formatText.toLowerCase()) {
          'flac' => const Color(0xFF10B981).withOpacity(0.12),
          'wav' => Colors.blue.withOpacity(0.12),
          _ => cfg.border,
        };

        return SizedBox(
          width: width,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                specText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final cfg = context.watch<UIThemeProvider>().currentTheme;
    final songs = libraryProvider.displaySongs;

    if (songs.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(40),
        child: Text(
          '没有找到符合条件的歌曲，请导入或调整过滤器',
          style: TextStyle(color: cfg.textSub, fontSize: 13),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = _tableWidth(constraints.maxWidth);
        final bodyHeight =
            math.max(0.0, constraints.maxHeight - _headerHeight).toDouble();

        return Scrollbar(
          thumbVisibility: true,
          controller: _verticalController,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Container(
                    height: _headerHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: cfg.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _leadingColumnWidth,
                          child: Center(
                            child: Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: cfg.textSub.withOpacity(0.65),
                            ),
                          ),
                        ),
                        for (final column in _columnOrder)
                          _buildHeaderCell(column, cfg),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: bodyHeight,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: (event) => _handlePointerMove(event, songs),
                      onPointerUp: (_) => _handlePointerUp(),
                      onPointerCancel: (_) => _handlePointerUp(),
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _verticalController,
                            itemCount: songs.length,
                            itemBuilder: (context, index) {
                              final song = songs[index];
                              final isCurrentlyPlaying =
                                  audioProvider.playingSong?.id == song.id;
                              final isActive =
                                  audioProvider.activeSong?.id == song.id;
                              final isSelected =
                                  _selectedSongIds.contains(song.id);
                              final primaryVersion = _primaryVersionFor(song);

                              return SizedBox(
                                width: tableWidth,
                                height: _rowHeight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (_) async {
                                    await _handleRowPrimaryTap(
                                      song,
                                      index,
                                      songs,
                                      libraryProvider,
                                      audioProvider,
                                    );
                                  },
                                  onSecondaryTapUp: (details) {
                                    _showContextMenu(
                                      context,
                                      details.globalPosition,
                                      song,
                                      libraryProvider,
                                    );
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? cfg.bgHover.withOpacity(0.12)
                                            : isActive
                                                ? cfg.bgHover.withOpacity(0.08)
                                                : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: cfg.border.withOpacity(0.45),
                                          ),
                                          left: BorderSide(
                                            color: isActive
                                                ? cfg.accent
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: _leadingColumnWidth,
                                            child: IconButton(
                                              icon: Icon(
                                                isCurrentlyPlaying &&
                                                        audioProvider.isPlaying
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_filled,
                                                size: 18,
                                                color: isCurrentlyPlaying
                                                    ? const Color(0xFF10B981)
                                                    : cfg.textSub,
                                              ),
                                              onPressed: () async {
                                                if (isCurrentlyPlaying) {
                                                  await audioProvider.playPause();
                                                  return;
                                                }
                                                try {
                                                  await audioProvider.playSong(
                                                    song,
                                                    songs,
                                                    libraryProvider.libraryPath,
                                                    audioServerPort:
                                                        libraryProvider
                                                            .audioServerPort,
                                                  );
                                                } catch (e) {
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        e.toString(),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                width: 36,
                                                height: 36,
                                              ),
                                            ),
                                          ),
                                          for (final column in _columnOrder)
                                            _buildCell(
                                              column,
                                              song,
                                              primaryVersion,
                                              cfg,
                                              isCurrentlyPlaying,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_isBoxSelecting &&
                              _selectionOrigin != null &&
                              _selectionCurrent != null)
                            Positioned(
                              left: math.min(
                                _selectionOrigin!.dx,
                                _selectionCurrent!.dx,
                              ),
                              top: math.min(
                                _selectionOrigin!.dy,
                                _selectionCurrent!.dy,
                              ),
                              width:
                                  (_selectionOrigin!.dx - _selectionCurrent!.dx)
                                      .abs(),
                              height:
                                  (_selectionOrigin!.dy - _selectionCurrent!.dy)
                                      .abs(),
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cfg.accent.withOpacity(0.12),
                                    border: Border.all(
                                      color: cfg.accent.withOpacity(0.55),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
