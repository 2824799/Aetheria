import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/ui/song_list_summary.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_actions.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_cells.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_column_layout.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_header.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_row.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_scroll_controller.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_scrollbar.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_selection.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Max interval between two primary taps to count as open/play double-tap.
const Duration kSongTablePrimaryTapInterval = Duration(milliseconds: 260);

class SongTableController {
  _SongTableState? _state;

  bool get isScrollbarDragging => _state?._isScrollbarDragging ?? false;

  /// Scrolls [songId] into view. Returns false when it is not in the list.
  Future<bool> revealSong(String songId) async {
    return await _state?._revealSong(songId) ?? false;
  }

  void _attach(_SongTableState state) => _state = state;

  void _detach(_SongTableState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }
}

/// Desktop song list: resizable columns, multi-selection and a context menu.
class SongTable extends StatefulWidget {
  final SongTableController? controller;

  const SongTable({super.key, this.controller});

  @override
  State<SongTable> createState() => _SongTableState();
}

class _SongTableState extends State<SongTable> {
  static const double _headerHeight = 44;
  static const double _rowHeight = 52;
  static const double _leadingColumnWidth = 52;
  static const double _scrollbarHitTestWidth = 18;

  final SongTableTextCache _textCache = SongTableTextCache();
  final SongTableScrollController _verticalController =
      SongTableScrollController();
  final SongTableSelection _selection = SongTableSelection();
  final SongTableColumnLayout _layout = SongTableColumnLayout();
  late final SongTableCells _cells = SongTableCells(
    textCache: _textCache,
    layout: _layout,
  );

  bool _isScrollbarDragging = false;
  DateTime? _lastTapAt;
  String? _lastTapSongId;
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _verticalController.addListener(_textCache.deferWarmup);
    _layout
      ..addListener(_onLayoutChanged)
      ..load();
  }

  @override
  void didUpdateWidget(covariant SongTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _layout.dispose();
    _textCache.dispose();
    _verticalController.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _revealSong(String songId) async {
    if (!mounted) return false;

    final songs = context.read<LibraryProvider>().displaySongs;
    final index = songs.indexWhere((song) => song.id == songId);
    if (index < 0) return false;

    if (!_verticalController.hasClients) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_verticalController.hasClients) return false;

    final position = _verticalController.position;
    final target =
        (index * _rowHeight - (position.viewportDimension - _rowHeight) / 2)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((position.pixels - target).abs() < 0.5) return true;

    if (AetherMotion.reduce(context)) {
      _verticalController.jumpTo(target);
      return true;
    }
    // Scale the duration with distance: a fixed short duration over hundreds
    // of rows reads as a jump cut rather than a scroll.
    final rows = (target - position.pixels).abs() / _rowHeight;
    final base = AetherMotion.normal.inMilliseconds;
    await _verticalController.animateTo(
      target,
      duration: Duration(
        milliseconds: (base + rows * 18).clamp(base, 900).round(),
      ),
      curve: AetherMotion.out,
    );
    return true;
  }

  bool get _multiSelectModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  Future<void> _play(Song song, List<Song> queue) async {
    final library = context.read<LibraryProvider>();
    try {
      await context.read<AudioPlayerProvider>().playSong(
        song,
        queue,
        library.libraryPath,
      );
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: e.toString(),
        kind: AetherToastKind.error,
      );
    }
  }

  /// Single click selects the row and opens its details; a second click
  /// within [kSongTablePrimaryTapInterval] also starts playback.
  Future<void> _handleRowTap(Song song, int index, List<Song> songs) async {
    if (_selection.suppressRowTap) return;

    final toggle = _multiSelectModifierPressed;
    final range = HardwareKeyboard.instance.isShiftPressed;
    _selection.click(song, index, songs, toggle: toggle, range: range);
    if (toggle || range) {
      _lastTapAt = null;
      _lastTapSongId = null;
      return;
    }

    context.read<AudioPlayerProvider>()
      ..setActiveSong(song)
      ..setDetailOpen(true);

    final now = DateTime.now();
    final previousTap = _lastTapAt;
    final isDoubleTap =
        _lastTapSongId == song.id &&
        previousTap != null &&
        now.difference(previousTap) < kSongTablePrimaryTapInterval;
    _lastTapSongId = song.id;
    _lastTapAt = now;

    if (isDoubleTap) {
      await _play(song, songs);
    }
  }

  void _handlePlayPressed(Song song, List<Song> songs, bool isLoaded) {
    if (isLoaded) {
      context.read<AudioPlayerProvider>().playPause();
    } else {
      _play(song, songs);
    }
  }

  void _openContextMenu(Offset position, Song song, int index) {
    // Right-clicking outside the selection retargets it to that row.
    if (!_selection.contains(song.id)) {
      _selection.selectOnly(song.id, index);
    }
    showSongTableContextMenu(
      context: context,
      position: position,
      songIds: _selection.ids,
      library: context.read<LibraryProvider>(),
      onDeleted: _selection.clear,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _textCache.deferWarmup();
    _selection.suppressRowTap = false;
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    // A press on the scrollbar track must not start a marquee.
    final viewport = context.findRenderObject() as RenderBox?;
    final viewportX =
        viewport?.globalToLocal(event.position).dx ?? event.localPosition.dx;
    if (_viewportWidth > 0 &&
        viewportX >= _viewportWidth - _scrollbarHitTestWidth) {
      return;
    }
    _selection.pressDown(
      event.localPosition,
      additive: _multiSelectModifierPressed,
    );
  }

  void _handlePointerMove(PointerMoveEvent event, List<Song> songs) {
    _selection.pressMove(
      event.localPosition,
      songs,
      scrollOffset: _verticalController.offset,
      rowHeight: _rowHeight,
    );
  }

  void _handleScrollbarDrag(bool dragging) {
    _isScrollbarDragging = dragging;
    if (dragging) {
      _textCache.suspendWarmup();
    } else {
      _textCache.resumeWarmup();
    }
  }

  double _tableWidth(double availableWidth) {
    // Keep a small logical-pixel guard. The table is often rendered through
    // FittedBox at a fractional scale; without it the Row can round 0.333px
    // wider than its viewport and paint overflow stripes over the last column.
    return math.max(
      availableWidth,
      _leadingColumnWidth + _layout.totalWidth + 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;
    final songs = library.displaySongs;

    _textCache.configurePrefetch(
      revision: songs,
      titles: songs.where(library.songHasLyrics).map((song) => song.title),
      titlesWithoutLyrics: songs
          .where((song) => !library.songHasLyrics(song))
          .map((song) => song.title),
      artists: songs.map((song) => song.artist ?? '未知歌手'),
    );
    _verticalController.smoothWheel = !AetherMotion.reduce(context);

    if (songs.isEmpty) {
      return SongListEmptyState(library: library);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final tableWidth = _tableWidth(constraints.maxWidth);
        final bodyHeight = math.max(
          0.0,
          constraints.maxHeight - _headerHeight,
        );

        return ScrollConfiguration(
          // The fixed track owns vertical scrolling. An automatically added
          // inner scrollbar would move with the horizontally scrolled table.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SongTableScrollbar(
            controller: _verticalController,
            headerHeight: _headerHeight,
            thumbColor: cfg.textTertiary.withValues(alpha: 0.5),
            onDraggingChanged: _handleScrollbarDrag,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    SongTableHeader(
                      layout: _layout,
                      height: _headerHeight,
                      leadingWidth: _leadingColumnWidth,
                    ),
                    SizedBox(
                      height: bodyHeight,
                      child: _buildBody(songs, library, tableWidth, cfg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    List<Song> songs,
    LibraryProvider library,
    double tableWidth,
    AppThemeConfig cfg,
  ) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) => _verticalController.pointerKind = event.kind,
      onPointerDown: _handlePointerDown,
      onPointerMove: (event) => _handlePointerMove(event, songs),
      onPointerUp: (_) => _selection.pressEnd(),
      onPointerCancel: (_) => _selection.pressEnd(),
      child: Stack(
        children: [
          ListView.builder(
            controller: _verticalController,
            itemExtent: _rowHeight,
            // Fast thumb jumps replace most visible rows. Keep the speculative
            // work bounded instead of building many extra rows of text and
            // tag scrollables.
            scrollCacheExtent: const ScrollCacheExtent.pixels(_rowHeight * 2),
            addAutomaticKeepAlives: false,
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return SongTableRow(
                song: song,
                width: tableWidth,
                height: _rowHeight,
                leadingWidth: _leadingColumnWidth,
                hasLyrics: library.songHasLyrics(song),
                cells: _cells,
                selection: _selection,
                onTap: () => _handleRowTap(song, index, songs),
                onPlayPressed: (isLoaded) =>
                    _handlePlayPressed(song, songs, isLoaded),
                onContextMenu: (position) =>
                    _openContextMenu(position, song, index),
              );
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('song-selection-overlay'),
                  painter: SongTableMarqueePainter(
                    _selection.marquee,
                    cfg.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
