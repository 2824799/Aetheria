import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_sheet.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
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

typedef MobileSongScrollSample = ({
  int index,
  double centeredOffset,
  double extent,
});

double estimateMobileSongScrollOffset({
  required int targetIndex,
  required int itemCount,
  required List<MobileSongScrollSample> samples,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  if (itemCount <= 1 || maxScrollExtent <= minScrollExtent) {
    return minScrollExtent;
  }

  if (samples.isEmpty) {
    final fraction = targetIndex.clamp(0, itemCount - 1) / (itemCount - 1);
    return minScrollExtent + (maxScrollExtent - minScrollExtent) * fraction;
  }

  final ordered = List<MobileSongScrollSample>.from(samples)
    ..sort((a, b) => a.index.compareTo(b.index));
  final anchor = ordered.reduce(
    (best, sample) =>
        (sample.index - targetIndex).abs() < (best.index - targetIndex).abs()
        ? sample
        : best,
  );

  var estimatedExtent =
      ordered.map((sample) => sample.extent).reduce((a, b) => a + b) /
      ordered.length;
  final first = ordered.first;
  final last = ordered.last;
  if (last.index != first.index) {
    final measuredExtent =
        (last.centeredOffset - first.centeredOffset) /
        (last.index - first.index);
    if (measuredExtent.isFinite && measuredExtent > 0) {
      estimatedExtent = measuredExtent;
    }
  }

  return (anchor.centeredOffset +
          (targetIndex - anchor.index) * estimatedExtent)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}

class MobileLayout extends StatefulWidget {
  const MobileLayout({super.key});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _songListController = ScrollController();
  final Map<String, BuildContext> _mountedSongContexts =
      <String, BuildContext>{};
  double _tagCollapseFactor = 0;
  bool _imeDismissedInBackground = false;
  bool _revealingPlayingSong = false;

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
    _songListController.dispose();
    _mountedSongContexts.clear();
    super.dispose();
  }

  void _mountSongContext(String songId, BuildContext itemContext) {
    _mountedSongContexts[songId] = itemContext;
  }

  void _unmountSongContext(String songId, BuildContext itemContext) {
    if (identical(_mountedSongContexts[songId], itemContext)) {
      _mountedSongContexts.remove(songId);
    }
  }

  Future<bool> _centerMountedSong(String songId) async {
    final itemContext = _mountedSongContexts[songId];
    final renderObject = itemContext?.findRenderObject();
    if (itemContext == null || renderObject == null || !renderObject.attached) {
      return false;
    }

    await Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: AetherMotion.duration(context, AetherMotion.slow),
      curve: AetherMotion.outQuart,
    );
    return mounted;
  }

  List<MobileSongScrollSample> _mountedSongSamples(
    Map<String, int> indexBySongId,
  ) {
    final samples = <MobileSongScrollSample>[];
    for (final entry in _mountedSongContexts.entries) {
      final index = indexBySongId[entry.key];
      final renderObject = entry.value.findRenderObject();
      if (index == null ||
          renderObject is! RenderBox ||
          !renderObject.attached) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) {
        continue;
      }
      samples.add((
        index: index,
        centeredOffset: viewport.getOffsetToReveal(renderObject, 0.5).offset,
        extent: renderObject.size.height,
      ));
    }
    return samples;
  }

  Future<void> _revealPlayingSong() async {
    if (_revealingPlayingSong) {
      return;
    }

    final audioProvider = context.read<AudioPlayerProvider>();
    final libraryProvider = context.read<LibraryProvider>();
    final playingSong = audioProvider.playingSong;
    if (playingSong == null) {
      return;
    }

    final songs = libraryProvider.displaySongs;
    final targetIndex = songs.indexWhere((song) => song.id == playingSong.id);
    if (targetIndex < 0) {
      showAetherToast(
        context,
        message: '当前歌曲不在这个歌单或筛选结果中',
        kind: AetherToastKind.info,
      );
      return;
    }

    _dismissKeyboard();
    _revealingPlayingSong = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_songListController.hasClients) {
        return;
      }

      if (await _centerMountedSong(playingSong.id)) {
        return;
      }

      final indexBySongId = <String, int>{
        for (var index = 0; index < songs.length; index++)
          songs[index].id: index,
      };
      for (var attempt = 0; attempt < 4; attempt++) {
        if (!mounted || !_songListController.hasClients) {
          return;
        }
        final position = _songListController.position;
        final targetOffset = estimateMobileSongScrollOffset(
          targetIndex: targetIndex,
          itemCount: songs.length,
          samples: _mountedSongSamples(indexBySongId),
          minScrollExtent: position.minScrollExtent,
          maxScrollExtent: position.maxScrollExtent,
        );

        if ((position.pixels - targetOffset).abs() >= 0.5) {
          if (AetherMotion.reduce(context)) {
            _songListController.jumpTo(targetOffset);
          } else {
            await _songListController.animateTo(
              targetOffset,
              duration: attempt == 0 ? AetherMotion.slow : AetherMotion.normal,
              curve: AetherMotion.outQuart,
            );
          }
        }

        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return;
        }
        if (await _centerMountedSong(playingSong.id)) {
          return;
        }
      }

      if (mounted) {
        showAetherToast(
          context,
          message: '暂时无法定位当前歌曲',
          kind: AetherToastKind.info,
        );
      }
    } finally {
      _revealingPlayingSong = false;
    }
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
    final audioProvider = context.read<AudioPlayerProvider>();
    final playbackState = context
        .select<
          AudioPlayerProvider,
          ({Song? playingSong, String? activeSongId, bool isPlaying})
        >(
          (provider) => (
            playingSong: provider.playingSong,
            activeSongId: provider.activeSong?.id,
            isPlaying: provider.isPlaying,
          ),
        );
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;

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

    final playingSong = playbackState.playingSong;
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
                          controller: _songListController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            AetherSpace.xl,
                            AetherSpace.md,
                            AetherSpace.xl,
                            miniPlayerReserve + bottomInset + AetherSpace.xxxl,
                          ),
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final isCurrentlyPlaying =
                                playingSong?.id == song.id;
                            final isActive =
                                playbackState.activeSongId == song.id;
                            return _MountedMobileSongItem(
                              key: ValueKey(song.id),
                              songId: song.id,
                              onMount: _mountSongContext,
                              onUnmount: _unmountSongContext,
                              child: MobileSongTile(
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
              onPlayingSongLongPress: _revealPlayingSong,
            ),
          ),
      ],
    );
  }
}

typedef _MobileSongContextCallback =
    void Function(String songId, BuildContext context);

class _MountedMobileSongItem extends StatefulWidget {
  const _MountedMobileSongItem({
    super.key,
    required this.songId,
    required this.onMount,
    required this.onUnmount,
    required this.child,
  });

  final String songId;
  final _MobileSongContextCallback onMount;
  final _MobileSongContextCallback onUnmount;
  final Widget child;

  @override
  State<_MountedMobileSongItem> createState() => _MountedMobileSongItemState();
}

class _MountedMobileSongItemState extends State<_MountedMobileSongItem> {
  @override
  void didUpdateWidget(covariant _MountedMobileSongItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      oldWidget.onUnmount(oldWidget.songId, context);
    }
  }

  @override
  void dispose() {
    widget.onUnmount(widget.songId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onMount(widget.songId, context);
    return widget.child;
  }
}
