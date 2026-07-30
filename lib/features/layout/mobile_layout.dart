import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_sheet.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/features/layout/mobile/mobile_actions.dart';
import 'package:aetheria/features/layout/mobile/mobile_drawer.dart';
import 'package:aetheria/features/layout/mobile/mobile_mini_player.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_context_menu.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_detail_sheet.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_tile.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';

class MobileLayout extends StatefulWidget {
  const MobileLayout({super.key});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  double _tagCollapseFactor = 0;
  bool _imeDismissedInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_imeDismissedInBackground) {
        _imeDismissedInBackground = true;
        _dismissKeyboard();
      }
    } else if (state == AppLifecycleState.resumed) {
      _imeDismissedInBackground = false;
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  void _openSongDetail(BuildContext context, Song song) {
    context.read<AudioPlayerProvider>().setActiveSong(song);
    showAetherSheet(
      context: context,
      isScrollControlled: true,
      decorate: false,
      maxHeightFactor: 0.95,
      builder: (context) => MobileSongDetailSheet(initialSong: song),
    );
  }

  Future<void> _playSong(
    BuildContext context,
    Song song,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
  ) async {
    _dismissKeyboard();
    audioProvider.setActiveSong(song);
    try {
      await audioProvider.playSong(
        song,
        libraryProvider.displaySongs,
        libraryProvider.libraryPath,
        audioServerPort: libraryProvider.audioServerPort,
      );
    } catch (e) {
      if (!context.mounted) return;
      await mobileShowPlayErrorDialog(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    final songs = libraryProvider.displaySongs;
    final playlists = libraryProvider.playlists;
    final activePlaylistId = libraryProvider.activePlaylistId;
    final activePlaylistName = activePlaylistId == null
        ? '全部音乐'
        : playlists
            .firstWhere(
              (p) => p.id == activePlaylistId,
              orElse: () =>
                  const Playlist(id: '', name: '未知歌单', createdAt: ''),
            )
            .name;

    final playingSong = audioProvider.playingSong;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniPlayerReserve = playingSong != null ? 88.0 : 0.0;

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          drawer: MobilePlaylistDrawer(
            libraryProvider: libraryProvider,
            cfg: cfg,
          ),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            leading: AetherIconButton(
              icon: Icons.menu_rounded,
              tooltip: '歌单',
              onPressed: () {
                _dismissKeyboard();
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            title: Padding(
              padding: const EdgeInsets.only(right: AetherSpace.sm),
              child: AetherSearchField(
                controller: _searchController,
                hintText: '搜索歌曲、歌手…',
                onChanged: libraryProvider.setSearchQuery,
              ),
            ),
            actions: [
              AetherIconButton(
                icon: Icons.label_outline,
                tooltip: '标签管理',
                onPressed: () {
                  _dismissKeyboard();
                  TagManagerModal.show(context);
                },
              ),
              AetherIconButton(
                icon: Icons.settings_outlined,
                tooltip: '系统设置',
                onPressed: () {
                  _dismissKeyboard();
                  SettingsModal.show(context);
                },
              ),
              const SizedBox(width: AetherSpace.xs),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpace.xl,
                  vertical: AetherSpace.md,
                ),
                child: TagFilter(
                  scrollCollapseFactor: _tagCollapseFactor,
                  onExpandRequested: () {
                    setState(() => _tagCollapseFactor = 0);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xl),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        activePlaylistName,
                        style: AetherType.labelStyle(cfg.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '共 ${songs.length} 首歌曲',
                      style: AetherType.captionStyle(cfg.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AetherSpace.sm),
              Expanded(
                child: songs.isEmpty
                    ? AetherEmptyState(
                        icon: Icons.library_music_outlined,
                        title: '暂无歌曲',
                        message: activePlaylistId == null
                            ? '请在设置中导入音源'
                            : '这个歌单还是空的，长按歌曲可以加入歌单',
                      )
                    : NotificationListener<ScrollUpdateNotification>(
                        onNotification: (notification) {
                          final delta = notification.scrollDelta ?? 0;
                          if (notification.metrics.axis == Axis.vertical &&
                              delta > 0 &&
                              _tagCollapseFactor < 1) {
                            setState(() {
                              _tagCollapseFactor = math.min(
                                1,
                                _tagCollapseFactor + delta / 140,
                              );
                            });
                          }
                          return false;
                        },
                        child: ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            AetherSpace.xl,
                            AetherSpace.md,
                            AetherSpace.xl,
                            miniPlayerReserve +
                                bottomInset +
                                AetherSpace.xxxl,
                          ),
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final isCurrentlyPlaying =
                                playingSong?.id == song.id;
                            final isActive =
                                audioProvider.activeSong?.id == song.id;
                            return MobileSongTile(
                              song: song,
                              cfg: cfg,
                              libraryProvider: libraryProvider,
                              isActive: isActive,
                              isCurrentlyPlaying: isCurrentlyPlaying,
                              onTap: () => _playSong(
                                context,
                                song,
                                libraryProvider,
                                audioProvider,
                              ),
                              onLongPress: () => showMobileSongContextMenu(
                                context,
                                song,
                                libraryProvider,
                                audioProvider,
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (playingSong != null)
          Positioned(
            left: AetherSpace.lg,
            right: AetherSpace.lg,
            bottom: bottomInset + AetherSpace.lg,
            child: MobileMiniPlayer(
              playingSong: playingSong,
              cfg: cfg,
              audioProvider: audioProvider,
              onOpenDetail: () => _openSongDetail(context, playingSong),
            ),
          ),
      ],
    );
  }
}
