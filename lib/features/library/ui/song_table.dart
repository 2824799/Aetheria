import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/features/library/ui/song_table/song_columns.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_cells.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Max interval between two primary taps to count as open/play double-tap.
const Duration kSongTablePrimaryTapInterval = Duration(milliseconds: 260);

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
  static const double _scrollbarHitTestWidth = 18;
  static const String _columnOrderKey = 'aetheria-song-table-column-order';
  static const String _columnWidthPrefix = 'aetheria-song-table-column-width-';

  final ScrollController _verticalController = ScrollController();
  final Set<String> _selectedSongIds = <String>{};
  final Map<SongColumnKey, double> _columnWidths = {
    for (final column in SongColumnKey.values) column: column.defaultWidth,
  };

  List<SongColumnKey> _columnOrder = List<SongColumnKey>.from(
    SongColumnKey.values,
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
  DateTime? _ignoreRowTapUntil;
  double _viewportWidth = 0;

  SongTableCellBuilder get _cellBuilder => SongTableCellBuilder(
    columnWidths: _columnWidths,
    columnOrder: _columnOrder,
    onResize: _resizeColumn,
    onReorder: _reorderColumn,
    headerHeight: _headerHeight,
  );

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
      final resolved = <SongColumnKey>[];
      for (final name in savedOrder) {
        for (final column in SongColumnKey.values) {
          if (column.name == name && !resolved.contains(column)) {
            resolved.add(column);
            break;
          }
        }
      }
      for (final column in SongColumnKey.values) {
        if (!resolved.contains(column)) {
          resolved.add(column);
        }
      }
      _columnOrder = resolved;
    }

    for (final column in SongColumnKey.values) {
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
    final ignoreUntil = _ignoreRowTapUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }

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
        now.difference(_lastPrimaryTapAt!) < kSongTablePrimaryTapInterval;

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
      showAetherToast(
        context,
        message: e.toString(),
        kind: AetherToastKind.error,
      );
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
    final result = await showAetherMenu<String>(
      context: context,
      globalPosition: position,
      items: _buildContextMenuItems(provider),
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
        showAetherToast(
          context,
          message: '已成功添加至歌单: ${playlist.name}',
          kind: AetherToastKind.success,
        );
      } catch (e) {
        if (!context.mounted) {
          return;
        }
        showAetherToast(
          context,
          message: '添加失败: $e',
          kind: AetherToastKind.error,
        );
      }
      return;
    }

    await _handleCommand(result, targetSongIds, provider);
  }

  List<AetherMenuItem<String>> _buildContextMenuItems(
    LibraryProvider provider,
  ) {
    final items = <AetherMenuItem<String>>[
      const AetherMenuItem(value: 'copy', label: '复制所选歌曲', icon: Icons.copy),
      const AetherMenuItem(
        value: 'cut',
        label: '剪切所选歌曲',
        icon: Icons.content_cut,
      ),
      const AetherMenuItem(
        value: 'delete',
        label: '彻底删除歌曲',
        icon: Icons.delete_forever,
        destructive: true,
      ),
    ];

    if (provider.activePlaylistId != null) {
      items.add(
        const AetherMenuItem(
          value: 'remove_playlist',
          label: '从当前歌单移除',
          icon: Icons.playlist_remove,
          warning: true,
        ),
      );
    }

    if (provider.playlists.isNotEmpty) {
      items.add(const AetherMenuItem.divider());
      for (final playlist in provider.playlists) {
        items.add(
          AetherMenuItem(
            value: 'playlist:${playlist.id}',
            label: '添加到歌单 · ${playlist.name}',
            icon: Icons.playlist_add,
          ),
        );
      }
    }

    final clipboardCount = provider.clipboard == null
        ? null
        : (provider.clipboard!['songIds'] as List).length;
    if (provider.activePlaylistId != null && clipboardCount != null) {
      items.add(const AetherMenuItem.divider());
      items.add(
        AetherMenuItem(
          value: 'paste',
          label: '粘贴歌曲 ($clipboardCount 首)',
          icon: Icons.paste,
        ),
      );
    }

    return items;
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
      await _confirmDeleteSongs(context, targetSongIds, provider);
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

  String _deleteSongSummary(List<String> songIds, LibraryProvider provider) {
    final songsById = {for (final song in provider.songs) song.id: song};
    final titles = songIds
        .map((id) => songsById[id]?.title)
        .whereType<String>()
        .toList();
    if (songIds.length == 1) {
      return titles.isNotEmpty ? '《${titles.first}》' : '这首歌曲';
    }
    if (titles.isEmpty) {
      return '这 ${songIds.length} 首歌曲';
    }
    final preview = titles.take(3).map((title) => '《$title》').join('、');
    final suffix = songIds.length > 3 ? ' 等 ${songIds.length} 首歌曲' : '';
    return '$preview$suffix';
  }

  Future<void> _confirmDeleteSongs(
    BuildContext context,
    List<String> songIds,
    LibraryProvider provider,
  ) async {
    final summary = _deleteSongSummary(songIds, provider);
    final confirmed = await showAetherConfirmDialog(
      context: context,
      title: '删除歌曲？',
      message: '即将从音乐库中删除 $summary，并同时删除本地物理音频文件。',
      confirmLabel: '继续删除',
      cancelLabel: '取消',
      dangerous: true,
      doubleConfirm: true,
      doubleConfirmMessage: '最后确认：$summary 的数据库记录和本地音频文件都会被删除，此操作不可撤销。',
      doubleConfirmLabel: '彻底删除',
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      for (final id in songIds) {
        await provider.deleteSong(id);
      }
      if (!mounted || !context.mounted) {
        return;
      }
      setState(() {
        _selectedSongIds.clear();
      });
      showAetherToast(
        context,
        message: '删除歌曲成功',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      showAetherToast(
        context,
        message: '删除失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    if (_viewportWidth > 0 &&
        event.localPosition.dx >= _viewportWidth - _scrollbarHitTestWidth) {
      _isPointerDownForSelection = false;
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

  void _resizeColumn(SongColumnKey column, double delta) {
    final nextWidth = (_columnWidths[column] ?? column.defaultWidth) + delta;
    setState(() {
      _columnWidths[column] = nextWidth.clamp(column.minWidth, 600).toDouble();
    });
    _saveColumnLayout();
  }

  void _reorderColumn(SongColumnKey dragged, SongColumnKey target) {
    if (dragged == target) {
      return;
    }
    final currentOrder = List<SongColumnKey>.from(_columnOrder);
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
    final contentWidth =
        _leadingColumnWidth +
        _columnOrder.fold<double>(
          0,
          (sum, column) => sum + (_columnWidths[column] ?? column.defaultWidth),
        );
    // Keep a small logical-pixel guard. The table is often rendered through
    // FittedBox at a fractional scale; without this guard the Row can be
    // rounded 0.333px wider than its viewport and Flutter paints overflow
    // stripes across the last column.
    return math.max(availableWidth, contentWidth + 1.0);
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

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.read<AudioPlayerProvider>();
    final playbackState = context
        .select<
          AudioPlayerProvider,
          ({String? playingSongId, String? activeSongId, bool isPlaying})
        >(
          (provider) => (
            playingSongId: provider.playingSong?.id,
            activeSongId: provider.activeSong?.id,
            isPlaying: provider.isPlaying,
          ),
        );
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;
    final songs = libraryProvider.displaySongs;

    if (songs.isEmpty) {
      return const AetherEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有符合条件的歌曲',
        message: '请导入音乐，或调整标签 / 搜索过滤器',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final tableWidth = _tableWidth(constraints.maxWidth);
        final bodyHeight = math
            .max(0.0, constraints.maxHeight - _headerHeight)
            .toDouble();

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
                        bottom: BorderSide(color: cfg.borderSubtle),
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
                              color: cfg.textSecondary.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                        for (final column in _columnOrder)
                          _cellBuilder.buildHeaderCell(column, cfg),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: bodyHeight,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: (event) =>
                          _handlePointerMove(event, songs),
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
                                  playbackState.playingSongId == song.id;
                              final isActive =
                                  playbackState.activeSongId == song.id;
                              final isSelected = _selectedSongIds.contains(
                                song.id,
                              );
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
                                            ? cfg.selection
                                            : isActive
                                            ? cfg.accentMuted
                                            : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: cfg.borderSubtle.withValues(
                                              alpha: 0.45,
                                            ),
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
                                            child: Listener(
                                              onPointerDown: (_) {
                                                _ignoreRowTapUntil =
                                                    DateTime.now().add(
                                                      const Duration(
                                                        milliseconds: 320,
                                                      ),
                                                    );
                                              },
                                              child: AetherIconButton(
                                                icon:
                                                    isCurrentlyPlaying &&
                                                        playbackState.isPlaying
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_filled,
                                                iconSize: AetherIconSize.lg,
                                                size: 36,
                                                color: isCurrentlyPlaying
                                                    ? cfg.success
                                                    : cfg.textSecondary,
                                                tooltip:
                                                    isCurrentlyPlaying &&
                                                        playbackState.isPlaying
                                                    ? '暂停'
                                                    : '播放',
                                                onPressed: () async {
                                                  if (isCurrentlyPlaying) {
                                                    await audioProvider
                                                        .playPause();
                                                    return;
                                                  }
                                                  try {
                                                    await audioProvider.playSong(
                                                      song,
                                                      songs,
                                                      libraryProvider
                                                          .libraryPath,
                                                      audioServerPort:
                                                          libraryProvider
                                                              .audioServerPort,
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    showAetherToast(
                                                      context,
                                                      message: e.toString(),
                                                      kind:
                                                          AetherToastKind.error,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                          for (final column in _columnOrder)
                                            _cellBuilder.buildCell(
                                              column,
                                              song,
                                              primaryVersion,
                                              cfg,
                                              isCurrentlyPlaying,
                                              libraryProvider.songHasLyrics(
                                                song,
                                              ),
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
                                    color: cfg.accent.withValues(alpha: 0.12),
                                    border: Border.all(
                                      color: cfg.accent.withValues(alpha: 0.55),
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AetherRadius.sm,
                                    ),
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
