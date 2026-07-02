import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  void _handleRowClick(Song song, int index, bool isCtrlPressed, bool isShiftPressed) {
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

  void _showContextMenu(BuildContext context, Offset position, Song song, LibraryProvider provider) {
    final activePlaylistId = provider.activePlaylistId;
    final clipboard = provider.clipboard;

    // Build the list of selected song IDs
    final targetSongIds = _selectedSongIds.contains(song.id) 
        ? List<String>.from(_selectedSongIds) 
        : [song.id];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: const [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('复制所选歌曲'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'cut',
          child: Row(
            children: const [
              Icon(Icons.content_cut, size: 16),
              SizedBox(width: 8),
              Text('剪切所选歌曲'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: const [
              Icon(Icons.delete_forever, color: Colors.redAccent, size: 16),
              SizedBox(width: 8),
              Text('彻底删除歌曲', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
        if (activePlaylistId != null)
          PopupMenuItem(
            value: 'remove_playlist',
            child: Row(
              children: const [
                Icon(Icons.playlist_remove, color: Colors.orangeAccent, size: 16),
                SizedBox(width: 8),
                Text('从当前歌单移除', style: TextStyle(color: Colors.orangeAccent)),
              ],
            ),
          ),
        if (provider.playlists.isNotEmpty)
          PopupMenuItem(
            value: 'add_to_playlist',
            child: Row(
              children: const [
                Icon(Icons.playlist_add, size: 16),
                SizedBox(width: 8),
                Text('添加到歌单...'),
              ],
            ),
          ),
        if (clipboard != null)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                const Icon(Icons.paste, size: 16),
                const SizedBox(width: 8),
                Text('粘贴歌曲 (${(clipboard['songIds'] as List).length} 首)'),
              ],
            ),
          ),
      ],
    ).then((val) {
      if (val == null) return;
      _handleCommand(val, targetSongIds, provider);
    });
  }

  void _handleCommand(String cmd, List<String> targetSongIds, LibraryProvider provider) async {
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
    } else if (cmd == 'add_to_playlist') {
      _showPlaylistSubmenu(context, targetSongIds, provider);
    } else if (cmd == 'paste') {
      if (activePlaylistId != null) {
        await provider.pasteSongs(activePlaylistId);
      }
    }
  }

  void _confirmDeleteSongs(BuildContext context, List<String> songIds, LibraryProvider provider) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('删除歌曲成功')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('删除失败: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistSubmenu(BuildContext context, List<String> songIds, LibraryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('添加到歌单'),
        children: provider.playlists.map((pl) {
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await provider.addSongsToPlaylist(pl.id, songIds);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已成功添加至歌单: ${pl.name}')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('添加失败: $e')),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(pl.name, style: const TextStyle(fontSize: 14)),
            ),
          );
        }).toList(),
      ),
    );
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
                child: Text('歌曲名称', style: TextStyle(color: cfg.textSub, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Expanded(
                flex: 3,
                child: Text('歌手', style: TextStyle(color: cfg.textSub, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Expanded(
                flex: 3,
                child: Text('标签', style: TextStyle(color: cfg.textSub, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Expanded(
                flex: 1,
                child: Text('版本数', textAlign: TextAlign.center, style: TextStyle(color: cfg.textSub, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Expanded(
                flex: 2,
                child: Text('默认音质', textAlign: TextAlign.center, style: TextStyle(color: cfg.textSub, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        ),

        // Table Body
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrentlyPlaying = audioProvider.playingSong?.id == song.id;
              final isActive = audioProvider.activeSong?.id == song.id;
              final isSelected = _selectedSongIds.contains(song.id);

              // Extract Spec Badge
              final primaryVersion = song.versions.firstWhere(
                (v) => v.isPrimary,
                orElse: () => song.versions.isNotEmpty ? song.versions.first : AudioVersion(
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
                final depth = (primaryVersion.format?.toLowerCase() == 'flac' && primaryVersion.bitDepth != null)
                    ? '${primaryVersion.bitDepth}b'
                    : '';
                final rate = primaryVersion.bitrate != null ? '${(primaryVersion.bitrate! / 1000).round()}kbps' : '';
                final loudnessStr = primaryVersion.loudness != null ? '${primaryVersion.loudness!.toStringAsFixed(1)}dB' : '';
                specText = [freq, depth, rate, loudnessStr].where((e) => e.isNotEmpty).join('/');
                if (specText.isEmpty) specText = '未知';
                formatText = primaryVersion.format ?? '';
              }

              return KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {},
                child: GestureDetector(
                  onTapUp: (details) {
                    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                    _handleRowClick(song, index, isCtrlPressed, isShiftPressed);
                    audioProvider.setActiveSong(song);
                  },
                  onDoubleTap: () async {
                    try {
                      await audioProvider.playSong(song, songs, libraryProvider.libraryPath, audioServerPort: libraryProvider.audioServerPort);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  onSecondaryTapUp: (details) {
                    _showContextMenu(context, details.globalPosition, song, libraryProvider);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? cfg.bgHover.withOpacity(0.12) 
                            : isActive 
                                ? cfg.bgHover.withOpacity(0.08) 
                                : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(color: cfg.border.withOpacity(0.5)),
                          left: BorderSide(
                            color: isActive ? cfg.accent : Colors.transparent,
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
                                isCurrentlyPlaying && audioProvider.isPlaying 
                                    ? Icons.pause_circle_filled 
                                    : Icons.play_circle_filled,
                                size: 18,
                                color: isCurrentlyPlaying ? const Color(0xFF10B981) : cfg.textSub,
                              ),
                              onPressed: () async {
                                if (isCurrentlyPlaying) {
                                  audioProvider.playPause();
                                } else {
                                  try {
                                    await audioProvider.playSong(song, songs, libraryProvider.libraryPath, audioServerPort: libraryProvider.audioServerPort);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
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
                                color: isCurrentlyPlaying ? cfg.accent : cfg.textMain,
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
                                  final col = t.color != null ? _parseHexColor(t.color!, cfg.accent) : cfg.accent;
                                  return Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: col.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border(left: BorderSide(color: col, width: 2.0)),
                                    ),
                                    child: Text(
                                      t.name,
                                      style: TextStyle(fontSize: 10, color: col, fontWeight: FontWeight.bold),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: formatText.toLowerCase() == 'flac'
                                      ? const Color(0xFF10B981).withOpacity(0.12)
                                      : formatText.toLowerCase() == 'wav'
                                          ? Colors.blue.withOpacity(0.12)
                                          : cfg.border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  specText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: formatText.toLowerCase() == 'flac'
                                        ? const Color(0xFF10B981)
                                        : formatText.toLowerCase() == 'wav'
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
        ),
      ],
    );
  }
}
