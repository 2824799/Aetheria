import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/layout/mobile/mobile_actions.dart';
import 'package:aetheria/features/layout/mobile/mobile_drawer.dart';
import 'package:aetheria/features/layout/mobile/mobile_mini_player.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_context_menu.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_reveal.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_tile.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';
import 'package:aetheria/features/library/ui/song_list_summary.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/src/rust/models/song.dart';

export 'package:aetheria/features/layout/mobile/mobile_song_reveal.dart'
    show MobileSongScrollSample, estimateMobileSongScrollOffset;

/// Phone layout: search bar, tag filter, song list and a floating mini
/// player. Playlists live in the drawer, song details in a bottom sheet.
class MobileLayout extends StatefulWidget {
  const MobileLayout({super.key});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout>
    with WidgetsBindingObserver {
  /// Scroll distance over which the tag filter folds away.
  static const double _tagCollapseDistance = 140;

  /// Room the floating mini player takes at the bottom of the list.
  static const double _miniPlayerReserve = 88;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _tagCollapseFactor = ValueNotifier(0);
  late final MobileSongRevealer _revealer = MobileSongRevealer(
    _scrollController,
  );
  bool _imeDismissedInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    _tagCollapseFactor.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android restores the keyboard over the app when it comes back to the
    // foreground unless the focus was dropped while leaving.
    if (state == AppLifecycleState.resumed) {
      _imeDismissedInBackground = false;
    } else if (state != AppLifecycleState.detached &&
        !_imeDismissedInBackground) {
      _imeDismissedInBackground = true;
      _dismissKeyboard();
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  bool _collapseTagsOnScroll(ScrollUpdateNotification notification) {
    final delta = notification.scrollDelta ?? 0;
    if (notification.metrics.axis == Axis.vertical &&
        notification.depth == 0 &&
        delta > 0 &&
        _tagCollapseFactor.value < 1) {
      _tagCollapseFactor.value = math.min(
        1,
        _tagCollapseFactor.value + delta / _tagCollapseDistance,
      );
    }
    return false;
  }

  Future<void> _revealPlayingSong() async {
    final playingId = context.read<AudioPlayerProvider>().playingSong?.id;
    if (playingId == null) return;

    final songIds = [
      for (final song in context.read<LibraryProvider>().displaySongs) song.id,
    ];
    final index = songIds.indexOf(playingId);
    if (index < 0) {
      showAetherToast(
        context,
        message: '当前歌曲不在这个歌单或筛选结果中',
        kind: AetherToastKind.info,
      );
      return;
    }

    _dismissKeyboard();
    final result = await _revealer.reveal(context, songIds, index);
    if (mounted && result == MobileSongRevealResult.unreachable) {
      showAetherToast(
        context,
        message: '暂时无法定位当前歌曲',
        kind: AetherToastKind.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final playback = context
        .select<AudioPlayerProvider, ({Song? playing, String? activeId})>(
          (provider) => (
            playing: provider.playingSong,
            activeId: provider.activeSong?.id,
          ),
        );
    final cfg = context.tokens;
    final playingSong = playback.playing;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      drawer: MobilePlaylistDrawer(library: library),
      appBar: _buildAppBar(library),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AetherSpace.xl,
                  AetherSpace.md,
                  AetherSpace.xl,
                  AetherSpace.lg,
                ),
                child: ValueListenableBuilder<double>(
                  valueListenable: _tagCollapseFactor,
                  builder: (context, factor, _) => TagFilter(
                    scrollCollapseFactor: factor,
                    onExpandRequested: () => _tagCollapseFactor.value = 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        songListTitle(library),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AetherType.titleLgStyle(cfg.textPrimary),
                      ),
                    ),
                    const SizedBox(width: AetherSpace.md),
                    Text(
                      songListCount(library),
                      style: AetherType.bodySmStyle(cfg.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AetherSpace.md),
              Expanded(
                child: _buildSongList(
                  library,
                  audio,
                  playingId: playingSong?.id,
                  activeId: playback.activeId,
                  bottomPadding:
                      (playingSong == null ? 0 : _miniPlayerReserve) +
                      bottomInset +
                      AetherSpace.xxxl,
                ),
              ),
            ],
          ),
          if (playingSong != null)
            Positioned(
              left: AetherSpace.lg,
              right: AetherSpace.lg,
              bottom: bottomInset + AetherSpace.lg,
              child: MobileMiniPlayer(
                playingSong: playingSong,
                cfg: cfg,
                audioProvider: audio,
                onOpenDetail: () =>
                    mobileOpenSongDetail(context, playingSong, audio),
                onPlayingSongLongPress: _revealPlayingSong,
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(LibraryProvider library) {
    return AppBar(
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
          onChanged: library.setSearchQuery,
        ),
      ),
      actions: [
        AetherIconButton(
          icon: Icons.label_outline_rounded,
          tooltip: '标签管理',
          onPressed: () {
            _dismissKeyboard();
            TagManagerModal.show(context);
          },
        ),
        AetherIconButton(
          icon: Icons.settings_outlined,
          tooltip: '设置',
          onPressed: () {
            _dismissKeyboard();
            SettingsModal.show(context);
          },
        ),
        const SizedBox(width: AetherSpace.xs),
      ],
    );
  }

  Widget _buildSongList(
    LibraryProvider library,
    AudioPlayerProvider audio, {
    required String? playingId,
    required String? activeId,
    required double bottomPadding,
  }) {
    final songs = library.displaySongs;
    if (songs.isEmpty) {
      return SongListEmptyState(library: library, touch: true);
    }

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _collapseTagsOnScroll,
      child: ListView.builder(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          AetherSpace.xl,
          0,
          AetherSpace.xl,
          bottomPadding,
        ),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return MobileSongAnchor(
            key: ValueKey(song.id),
            songId: song.id,
            revealer: _revealer,
            child: MobileSongTile(
              song: song,
              hasLyrics: library.songHasLyrics(song),
              isActive: song.id == activeId,
              isPlaying: song.id == playingId,
              onTap: () {
                _dismissKeyboard();
                mobilePlaySong(context, song, library, audio);
              },
              onLongPress: () =>
                  showMobileSongContextMenu(context, song, library, audio),
            ),
          );
        },
      ),
    );
  }
}
