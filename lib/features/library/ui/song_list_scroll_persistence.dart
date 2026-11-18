import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_scroll_controller.dart';

/// Persists and restores a song list's vertical scroll offset per view scope
/// (All Songs, each playlist, and active Phigros chapter) across restarts and
/// in-session playlist switches.
class SongListScrollPersistence {
  SongListScrollPersistence({
    required this.viewport,
    required this.controller,
    required this.isMounted,
  });

  static const Duration _coalesceInterval = Duration(milliseconds: 200);

  final SongListViewport viewport;
  final PendingInitialScrollOffset controller;
  final bool Function() isMounted;

  LibraryProvider? _library;
  String? _activeScope;
  bool _hasSyncedScope = false;
  bool _pendingRestore = false;
  bool _isRestoring = false;
  bool _loadRequested = false;
  bool _userScrolledBeforePrefsLoaded = false;
  bool _hasDirtyPersist = false;
  Timer? _persistTimer;
  int _restoreGeneration = 0;

  /// True while programmatically jumping to a saved offset on scope switch,
  /// so collapsible headers can ignore the synthetic scroll delta.
  bool get isRestoring => _isRestoring;

  void init() {
    controller.addListener(_handleScrollOffsetChanged);
  }

  void syncWithLibrary(LibraryProvider library, {required bool hasSongs}) {
    _library = library;
    final scope = library.songListScrollScope;
    final songsReady = hasSongs && !library.isLoadingActivePlaylistSongs;

    if (!library.hasLoadedSongListScrollOffsets && !_loadRequested) {
      _loadRequested = true;
      unawaited(_loadAndRestore(library));
    }

    if (!songsReady) {
      if (!_hasSyncedScope || _activeScope != scope) {
        _hasSyncedScope = true;
        _activeScope = scope;
        _pendingRestore = true;
        controller.pendingInitialScrollOffset = library
            .savedSongListScrollOffset(viewport, scope);
      }
      return;
    }

    if (!_hasSyncedScope || _activeScope != scope || _pendingRestore) {
      _hasSyncedScope = true;
      _activeScope = scope;
      _pendingRestore = false;
      final targetOffset = library.savedSongListScrollOffset(viewport, scope);
      controller.pendingInitialScrollOffset = targetOffset;
      if (controller.hasClients) {
        _schedulePostFrameRestore(targetOffset, expectedScope: scope);
      }
    }
  }

  Future<void> _loadAndRestore(LibraryProvider library) async {
    await library.ensureSongListScrollOffsetsLoaded();
    if (!isMounted() || _userScrolledBeforePrefsLoaded) {
      return;
    }
    final scope = _activeScope;
    if (!_hasSyncedScope || scope == null) {
      return;
    }
    final targetOffset = library.savedSongListScrollOffset(viewport, scope);
    controller.pendingInitialScrollOffset = targetOffset;
    if (!controller.hasClients || _pendingRestore) {
      return;
    }
    if ((controller.offset - targetOffset).abs() < 0.5) {
      return;
    }
    _schedulePostFrameRestore(targetOffset, expectedScope: scope);
  }

  void _schedulePostFrameRestore(
    double targetOffset, {
    required String? expectedScope,
  }) {
    final generation = ++_restoreGeneration;
    _isRestoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _restoreGeneration) {
        return;
      }
      try {
        if (!isMounted() || !controller.hasClients) {
          return;
        }
        if (_activeScope != expectedScope) {
          return;
        }
        final position = controller.position;
        final clamped = targetOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - clamped).abs() >= 0.5) {
          controller.jumpTo(clamped);
        }
      } finally {
        if (generation == _restoreGeneration) {
          _isRestoring = false;
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleScrollOffsetChanged() {
    if (_isRestoring || _pendingRestore || !controller.hasClients) {
      return;
    }
    final library = _library;
    final scope = _activeScope;
    if (library == null || scope == null || !_hasSyncedScope) {
      return;
    }
    if (library.isLoadingActivePlaylistSongs) {
      return;
    }
    _userScrolledBeforePrefsLoaded = true;
    final changed = library.recordSongListScrollOffset(
      viewport,
      scope,
      controller.offset,
    );
    if (!changed) {
      return;
    }
    _hasDirtyPersist = true;
    _persistTimer ??= Timer(_coalesceInterval, flushPendingPersist);
  }

  bool handleScrollEnd(ScrollEndNotification notification) {
    if (notification.metrics.axis == Axis.vertical && notification.depth == 0) {
      flushPendingPersist();
    }
    return false;
  }

  void flushPendingPersist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (!_hasDirtyPersist) {
      return;
    }
    _hasDirtyPersist = false;
    final library = _library;
    if (library != null) {
      unawaited(library.persistSongListScrollOffsets());
    }
  }

  void dispose() {
    controller.removeListener(_handleScrollOffsetChanged);
    flushPendingPersist();
  }
}
