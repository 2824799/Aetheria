import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';

class SongTable extends StatefulWidget {
  const SongTable({super.key});

  @override
  State<SongTable> createState() => _SongTableState();
}

class _SongTableState extends State<SongTable> {
  final List<String> _selectedSongIds = [];
  int _lastSelectedIndex = -1;
  final ScrollController _scrollController = ScrollController();
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  bool _isBoxSelecting = false;
  OverlayEntry? _contextMenuEntry;

  static const double _rowHeight = 49.0;

  @override
  void dispose() {
    _contextMenuEntry?.remove();
    _scrollController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  void _handleRowClick(
    Song song,
    int index,
    bool isCtrlPressed,
    bool isShiftPressed,
  ) {
    setState(() {
      if (isCtrlPressed) {
        if (_selectedSongIds.contains(song.id)) {
          _selectedSongIds.remove(song.id);
        } else {
          _selectedSongIds.add(song.id);
        }
        _lastSelectedIndex = index;
      } else if (isShiftPressed && _lastSelectedIndex != -1) {
        final songs = context.read<LibraryProvider>().displaySongs;
        final start = index < _lastSelectedIndex ? index : _lastSelectedIndex;
        final end = index > _lastSelectedIndex ? index : _lastSelectedIndex;

        _selectedSongIds.clear();
        for (int i = start; i <= end; i++) {
          _selectedSongIds.add(songs[i].id);
        }
      } else {
        _selectedSongIds.clear();
        _selectedSongIds.add(song.id);
        _lastSelectedIndex = index;
      }
    });
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    Song song,
    LibraryProvider provider,
  ) {
    final activePlaylistId = provider.activePlaylistId;
    final clipboard = provider.clipboard;
    final cfg = context.read<UIThemeProvider>().currentTheme;

    final targetSongIds = _selectedSongIds.contains(song.id)
        ? List<String>.from(_selectedSongIds)
        : [song.id];

    if (!_selectedSongIds.contains(song.id)) {
      setState(() {
        _selectedSongIds
          ..clear()
          ..add(song.id);
        _lastSelectedIndex = provider.displaySongs.indexWhere(
          (s) => s.id == song.id,
        );
      });
    }

    _contextMenuEntry?.remove();
    _contextMenuEntry = OverlayEntry(
      builder: (overlayContext) => _SongContextMenu(
        position: position,
        cfg: cfg,
        playlists: provider.playlists,
        activePlaylistId: activePlaylistId,
        clipboardCount: clipboard == null
            ? null
            : (clipboard['songIds'] as List).length,
        onClose: _closeContextMenu,
        onCommand: (cmd) {
          _closeContextMenu();
          _handleCommand(cmd, targetSongIds, provider);
        },
        onAddToPlaylist: (playlistId, playlistName) async {
          _closeContextMenu();
          try {
            await provider.addSongsToPlaylist(playlistId, targetSongIds);
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('已成功添加至歌单: $playlistName')));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('添加失败: $e')));
          }
        },
      ),
    );
    Overlay.of(context).insert(_contextMenuEntry!);
  }

  void _closeContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  void _handleCommand(
    String cmd,
    List<String> targetSongIds,
    LibraryProvider provider,
  ) async {
    final activePlaylistId = provider.activePlaylistId;
    if (cmd == 'copy') {
      provider.setClipboard('copy', targetSongIds, activePlaylistId);
    } else if (cmd == 'cut') {
      provider.setClipboard('cut', targetSongIds, activePlaylistId);
    } else if (cmd == 'delete') {
      _confirmDeleteSongs(context, targetSongIds, provider);
    } else if (cmd == 'remove_playlist') {
      if (activePlaylistId != null) {
        await provider.removeSongsFromPlaylist(activePlaylistId, targetSongIds);
      }
    } else if (cmd == 'paste') {
      if (activePlaylistId != null) {
        await provider.pasteSongs(activePlaylistId);
      }
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
        content: Text('您确定要将这 ${songIds.length} 首歌曲从音乐库彻底删除吗？这会同时删除本地物理音频文件！'),
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
                setState(() {
                  _selectedSongIds.clear();
                });
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('删除歌曲成功')));
              } catch (e) {
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

  void _startBoxSelection(DragStartDetails details) {
    if (!HardwareKeyboard.instance.isShiftPressed) return;
    _closeContextMenu();
    setState(() {
      _selectionStart = details.localPosition;
      _selectionCurrent = details.localPosition;
      _isBoxSelecting = true;
    });
  }

  void _updateBoxSelection(DragUpdateDetails details, List<Song> songs) {
    if (!_isBoxSelecting || _selectionStart == null) return;
    setState(() {
      _selectionCurrent = details.localPosition;
      _selectSongsInRect(songs);
    });
  }

  void _endBoxSelection() {
    setState(() {
      _selectionStart = null;
      _selectionCurrent = null;
      _isBoxSelecting = false;
    });
  }

  void _selectSongsInRect(List<Song> songs) {
    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) return;

    final top = math.min(start.dy, current.dy) + _scrollController.offset;
    final bottom = math.max(start.dy, current.dy) + _scrollController.offset;
    final first = (top / _rowHeight).floor().clamp(0, songs.length - 1);
    final last = (bottom / _rowHeight).floor().clamp(0, songs.length - 1);

    _selectedSongIds
      ..clear()
      ..addAll(songs.sublist(first, last + 1).map((s) => s.id));
    _lastSelectedIndex = last;
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

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

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cfg.border)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 40), // Play status width
              Expanded(
                flex: 4,
                child: Text(
                  '歌曲名称',
                  style: TextStyle(
                    color: cfg.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '歌手',
                  style: TextStyle(
                    color: cfg.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '标签',
                  style: TextStyle(
                    color: cfg.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  '版本数',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cfg.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '默认音质',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cfg.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Table Body
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: _startBoxSelection,
                onPanUpdate: (details) => _updateBoxSelection(details, songs),
                onPanEnd: (_) => _endBoxSelection(),
                onPanCancel: _endBoxSelection,
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final isCurrentlyPlaying =
                            audioProvider.playingSong?.id == song.id;
                        final isActive =
                            audioProvider.activeSong?.id == song.id;
                        final isSelected = _selectedSongIds.contains(song.id);

                        // Extract Spec Badge
                        final primaryVersion = song.versions.firstWhere(
                          (v) => v.isPrimary,
                          orElse: () => song.versions.isNotEmpty
                              ? song.versions.first
                              : AudioVersion(
                                  id: '',
                                  songId: '',
                                  filepath: '',
                                  originalName: '',
                                  duration: 0,
                                  fileSize: 0,
                                  isEnabled: false,
                                  isPrimary: false,
                                ),
                        );

                        String specText = '未知';
                        String formatText = '';
                        if (primaryVersion.id.isNotEmpty) {
                          final freq = primaryVersion.sampleRate != null
                              ? '${(primaryVersion.sampleRate! / 1000).toStringAsFixed(1).replaceAll('.0', '')}k'
                              : '';
                          final depth =
                              (primaryVersion.format?.toLowerCase() == 'flac' &&
                                  primaryVersion.bitDepth != null)
                              ? '${primaryVersion.bitDepth}b'
                              : '';
                          final rate = primaryVersion.bitrate != null
                              ? '${(primaryVersion.bitrate! / 1000).round()}kbps'
                              : '';
                          final loudnessStr = primaryVersion.loudness != null
                              ? '${primaryVersion.loudness!.toStringAsFixed(1)}dB'
                              : '';
                          specText = [
                            freq,
                            depth,
                            rate,
                            loudnessStr,
                          ].where((e) => e.isNotEmpty).join('/');
                          if (specText.isEmpty) specText = '未知';
                          formatText = primaryVersion.format ?? '';
                        }

                        return KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (event) {},
                          child: GestureDetector(
                            onTapUp: (details) {
                              final isCtrlPressed =
                                  HardwareKeyboard.instance.isControlPressed ||
                                  HardwareKeyboard.instance.isMetaPressed;
                              final isShiftPressed =
                                  HardwareKeyboard.instance.isShiftPressed;
                              _handleRowClick(
                                song,
                                index,
                                isCtrlPressed,
                                isShiftPressed,
                              );
                              audioProvider.setActiveSong(song);
                              audioProvider.setDetailOpen(true);
                            },
                            onDoubleTap: () async {
                              try {
                                await audioProvider.playSong(
                                  song,
                                  songs,
                                  libraryProvider.libraryPath,
                                  audioServerPort:
                                      libraryProvider.audioServerPort,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cfg.bgHover.withOpacity(0.12)
                                      : isActive
                                      ? cfg.bgHover.withOpacity(0.08)
                                      : Colors.transparent,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: cfg.border.withOpacity(0.5),
                                    ),
                                    left: BorderSide(
                                      color: isActive
                                          ? cfg.accent
                                          : Colors.transparent,
                                      width: 3.0,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Play/Pause Action
                                    Container(
                                      width: 40,
                                      alignment: Alignment.centerLeft,
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
                                            audioProvider.playPause();
                                          } else {
                                            try {
                                              await audioProvider.playSong(
                                                song,
                                                songs,
                                                libraryProvider.libraryPath,
                                                audioServerPort: libraryProvider
                                                    .audioServerPort,
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(e.toString()),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),

                                    // Song Title
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        song.title,
                                        style: TextStyle(
                                          color: isCurrentlyPlaying
                                              ? cfg.accent
                                              : cfg.textMain,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          fontFamily: 'Outfit',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Artist
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        song.artist ?? '未知歌手',
                                        style: TextStyle(
                                          color: cfg.textSub,
                                          fontSize: 12,
                                          fontFamily: 'Outfit',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Tags
                                    Expanded(
                                      flex: 3,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: song.tags.map((t) {
                                            final col = t.color != null
                                                ? _parseHexColor(
                                                    t.color!,
                                                    cfg.accent,
                                                  )
                                                : cfg.accent;
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: col.withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: col,
                                                    width: 2.0,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                t.name,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: col,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),

                                    // Versions count
                                    Expanded(
                                      flex: 1,
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

                                    // Spec Badges
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                formatText.toLowerCase() ==
                                                    'flac'
                                                ? const Color(
                                                    0xFF10B981,
                                                  ).withOpacity(0.12)
                                                : formatText.toLowerCase() ==
                                                      'wav'
                                                ? Colors.blue.withOpacity(0.12)
                                                : cfg.border,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            specText,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  formatText.toLowerCase() ==
                                                      'flac'
                                                  ? const Color(0xFF10B981)
                                                  : formatText.toLowerCase() ==
                                                        'wav'
                                                  ? Colors.blue
                                                  : cfg.textSub,
                                            ),
                                          ),
                                        ),
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
                        _selectionStart != null &&
                        _selectionCurrent != null)
                      Positioned(
                        left: math.min(
                          _selectionStart!.dx,
                          _selectionCurrent!.dx,
                        ),
                        top: math.min(
                          _selectionStart!.dy,
                          _selectionCurrent!.dy,
                        ),
                        width:
                            (math.max(
                                      _selectionStart!.dx,
                                      _selectionCurrent!.dx,
                                    ) -
                                    math.min(
                                      _selectionStart!.dx,
                                      _selectionCurrent!.dx,
                                    ))
                                .abs(),
                        height:
                            (math.max(
                                      _selectionStart!.dy,
                                      _selectionCurrent!.dy,
                                    ) -
                                    math.min(
                                      _selectionStart!.dy,
                                      _selectionCurrent!.dy,
                                    ))
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SongContextMenu extends StatefulWidget {
  final Offset position;
  final AppThemeConfig cfg;
  final List<dynamic> playlists;
  final String? activePlaylistId;
  final int? clipboardCount;
  final VoidCallback onClose;
  final ValueChanged<String> onCommand;
  final Future<void> Function(String playlistId, String playlistName)
  onAddToPlaylist;

  const _SongContextMenu({
    required this.position,
    required this.cfg,
    required this.playlists,
    required this.activePlaylistId,
    required this.clipboardCount,
    required this.onClose,
    required this.onCommand,
    required this.onAddToPlaylist,
  });

  @override
  State<_SongContextMenu> createState() => _SongContextMenuState();
}

class _SongContextMenuState extends State<_SongContextMenu> {
  bool _showPlaylistMenu = false;
  final GlobalKey _addToPlaylistKey = GlobalKey();
  double _addToPlaylistY = 0.0;

  void _measureAddToPlaylistY() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = _addToPlaylistKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        setState(() {
          _addToPlaylistY = position.dy - widget.position.dy;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showPlaylistMenu && _addToPlaylistY == 0.0) {
      _measureAddToPlaylistY();
    }

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onClose,
        onSecondaryTap: widget.onClose,
        child: Stack(
          children: [
            Positioned(
              left: widget.position.dx,
              top: widget.position.dy,
              child: MouseRegion(
                onExit: (_) => setState(() => _showPlaylistMenu = false),
                child: Material(
                  color: Colors.transparent,
                  child: Stack(
                    children: [
                      _menuShell(
                        width: 184,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _item(
                              Icons.copy,
                              '复制所选歌曲',
                              () => widget.onCommand('copy'),
                            ),
                            _item(
                              Icons.content_cut,
                              '剪切所选歌曲',
                              () => widget.onCommand('cut'),
                            ),
                            _item(
                              Icons.delete_forever,
                              '彻底删除歌曲',
                              () => widget.onCommand('delete'),
                              color: Colors.redAccent,
                            ),
                            if (widget.activePlaylistId != null)
                              _item(
                                Icons.playlist_remove,
                                '从当前歌单移除',
                                () => widget.onCommand('remove_playlist'),
                                color: Colors.orangeAccent,
                              ),
                            if (widget.playlists.isNotEmpty)
                              MouseRegion(
                                key: _addToPlaylistKey,
                                onEnter: (_) {
                                  setState(() => _showPlaylistMenu = true);
                                  _measureAddToPlaylistY();
                                },
                                child: _item(
                                  Icons.playlist_add,
                                  '添加到歌单',
                                  () {},
                                  trailing: Icons.chevron_right,
                                ),
                              ),
                            if (widget.clipboardCount != null)
                              _item(
                                Icons.paste,
                                '粘贴歌曲 (${widget.clipboardCount} 首)',
                                () => widget.onCommand('paste'),
                              ),
                          ],
                        ),
                      ),
                      if (_showPlaylistMenu)
                        Positioned(
                          left: 190,
                          top: _addToPlaylistY,
                          child: _menuShell(
                            width: 172,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 260),
                              child: ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: widget.playlists.map((pl) {
                                  return _item(
                                    Icons.queue_music,
                                    pl.name as String,
                                    () => widget.onAddToPlaylist(
                                      pl.id as String,
                                      pl.name as String,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuShell({required double width, required Widget child}) {
    final cfg = widget.cfg;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cfg.bgPanel.withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.border.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _item(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
    IconData? trailing,
  }) {
    final cfg = widget.cfg;
    final itemColor = color ?? cfg.textMain;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 15, color: itemColor.withOpacity(0.92)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: itemColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Outfit',
                  letterSpacing: 0.1,
                ),
              ),
            ),
            if (trailing != null) Icon(trailing, size: 16, color: cfg.textSub),
          ],
        ),
      ),
    );
  }
}
