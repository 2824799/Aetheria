import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/core/widgets/aether_tabs.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/layout/mobile/mobile_detail_tabs.dart';
import 'package:aetheria/features/player/ui/song_cover_art.dart';
import 'package:aetheria/src/rust/models/song.dart';

class MobileSongDetailSheet extends StatefulWidget {
  final Song initialSong;

  const MobileSongDetailSheet({super.key, required this.initialSong});

  @override
  State<MobileSongDetailSheet> createState() => _MobileSongDetailSheetState();
}

class _MobileSongDetailSheetState extends State<MobileSongDetailSheet> {
  String activeTab = 'lyrics';
  bool showVolumeSlider = false;
  late TextEditingController titleController;
  late TextEditingController artistController;
  late FocusNode focusNodeTitle;
  late FocusNode focusNodeArtist;
  String? lastSongId;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.initialSong.title);
    artistController = TextEditingController(
      text: widget.initialSong.artist ?? '未知歌手',
    );
    focusNodeTitle = FocusNode();
    focusNodeArtist = FocusNode();
    lastSongId = widget.initialSong.id;

    focusNodeTitle.addListener(_onTitleFocusChange);
    focusNodeArtist.addListener(_onArtistFocusChange);
  }

  @override
  void dispose() {
    titleController.dispose();
    artistController.dispose();
    focusNodeTitle.dispose();
    focusNodeArtist.dispose();
    super.dispose();
  }

  void _onTitleFocusChange() {
    if (!focusNodeTitle.hasFocus) {
      _saveMetadata();
    }
  }

  void _onArtistFocusChange() {
    if (!focusNodeArtist.hasFocus) {
      _saveMetadata();
    }
  }

  Future<void> _saveMetadata() async {
    if (lastSongId == null) return;
    final libraryProvider = context.read<LibraryProvider>();
    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == lastSongId,
      orElse: () => widget.initialSong,
    );
    final newTitle = titleController.text.trim();
    final newArtistText = artistController.text.trim();
    final newArtist = newArtistText == '未知歌手' ? '' : newArtistText;

    if (newTitle.isNotEmpty &&
        (newTitle != song.title || newArtist != (song.artist ?? ''))) {
      try {
        await libraryProvider.updateSongMetadata(song.id, newTitle, newArtist);
      } catch (e) {
        if (!mounted) return;
        showAetherToast(
          context,
          message: '保存元数据失败: $e',
          kind: AetherToastKind.error,
        );
      }
    }
  }

  Widget _buildVersionHeader(Song song, AppThemeConfig cfg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xxl,
        AetherSpace.xs,
        AetherSpace.xxl,
        AetherSpace.lg - 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SongCoverArt(
            song: song,
            cfg: cfg,
            size: 108,
            borderRadius: AetherRadius.xl,
            iconSize: AetherIconSize.hero + 12,
          ),
          const SizedBox(height: AetherSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xxl),
            child: AetherTextField.plain(
              controller: titleController,
              focusNode: focusNodeTitle,
              onSubmitted: (_) => _saveMetadata(),
              style: AetherType.titleStyle(cfg.textPrimary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xxl),
            child: AetherTextField.plain(
              controller: artistController,
              focusNode: focusNodeArtist,
              onSubmitted: (_) => _saveMetadata(),
              style: AetherType.bodySmStyle(cfg.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  IconData _playModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.shuffle:
        return Icons.shuffle;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.list:
        return Icons.repeat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final cfg = context.watch<UIThemeProvider>().currentTheme;

    final currentActiveSong = audioProvider.activeSong ?? widget.initialSong;

    if (currentActiveSong.id != lastSongId) {
      lastSongId = currentActiveSong.id;
      final songData = libraryProvider.songs.firstWhere(
        (s) => s.id == currentActiveSong.id,
        orElse: () => currentActiveSong,
      );
      titleController.text = songData.title;
      artistController.text = songData.artist ?? '未知歌手';
    }

    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == currentActiveSong.id,
      orElse: () => currentActiveSong,
    );

    final isPlayingThisSong = audioProvider.playingSong?.id == song.id;
    final durationMin = (audioProvider.totalDuration.inSeconds / 60).floor();
    final durationSec = (audioProvider.totalDuration.inSeconds % 60)
        .toString()
        .padLeft(2, '0');
    final curMin = (audioProvider.currentPosition.inSeconds / 60).floor();
    final curSec = (audioProvider.currentPosition.inSeconds % 60)
        .toString()
        .padLeft(2, '0');

    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progress = totMs > 0 ? (curMs / totMs).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: BoxDecoration(
        gradient: cfg.bgApp,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AetherRadius.xxl),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AetherSpace.xl,
                vertical: AetherSpace.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AetherIconButton(
                    icon: Icons.keyboard_arrow_down,
                    size: 44,
                    iconSize: AetherIconSize.hero - 4,
                    color: cfg.textPrimary,
                    tooltip: '关闭',
                    onPressed: () {
                      _saveMetadata();
                      Navigator.of(context).pop();
                    },
                  ),
                  Text(
                    isPlayingThisSong ? '正在播放' : '歌曲详情',
                    style: AetherType.labelStyle(cfg.textSecondary).copyWith(
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: buildMobileDetailTabContent(
                context,
                song,
                activeTab,
                libraryProvider,
                audioProvider,
                cfg,
                () {
                  setState(() {
                    activeTab = 'lyric_manager';
                  });
                },
                _buildVersionHeader(song, cfg),
              ),
            ),
            Divider(height: 1, color: cfg.borderSubtle),
            AetherTabBar(
              value: activeTab,
              onChanged: (id) => setState(() => activeTab = id),
              fontSize: AetherType.bodySm,
              tabs: [
                const AetherTabItem(id: 'lyrics', label: '滚动歌词'),
                const AetherTabItem(id: 'lyric_manager', label: '歌词管理'),
                AetherTabItem(
                  id: 'tags',
                  label: '关联标签 (${song.tags.length})',
                ),
                AetherTabItem(
                  id: 'versions',
                  label: '音频源 (${song.versions.length})',
                ),
              ],
            ),
            if (isPlayingThisSong) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpace.xxxl,
                  vertical: AetherSpace.md,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$curMin:$curSec',
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                        Text(
                          '$durationMin:$durationSec',
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                      ],
                    ),
                    AetherSlider(
                      value: progress,
                      onChanged: (val) {
                        final targetMs =
                            (audioProvider.totalDuration.inMilliseconds * val)
                                .toInt();
                        audioProvider.seek(Duration(milliseconds: targetMs));
                      },
                    ),
                  ],
                ),
              ),
              if (showVolumeSlider)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: AetherSpace.xxxl,
                    left: AetherSpace.xl,
                    right: AetherSpace.xl,
                  ),
                  child: Row(
                    children: [
                      AetherIconButton(
                        icon: audioProvider.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_up,
                        size: 40,
                        iconSize: AetherIconSize.xl,
                        color: audioProvider.volume == 0
                            ? cfg.textSecondary
                            : cfg.accent,
                        selected: audioProvider.volume > 0,
                        tooltip: '静音切换',
                        onPressed: () {
                          audioProvider.setVolume(
                            audioProvider.volume == 0 ? 0.8 : 0,
                          );
                        },
                      ),
                      Expanded(
                        child: AetherSlider(
                          value: audioProvider.volume,
                          onChanged: audioProvider.setVolume,
                        ),
                      ),
                      AetherIconButton(
                        icon: Icons.close,
                        size: 40,
                        iconSize: AetherIconSize.xl,
                        color: cfg.textSecondary,
                        tooltip: '关闭音量',
                        onPressed: () {
                          setState(() => showVolumeSlider = false);
                        },
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: AetherSpace.xxxl,
                    left: AetherSpace.xl,
                    right: AetherSpace.xl,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      AetherIconButton(
                        icon: _playModeIcon(audioProvider.playMode),
                        size: 40,
                        iconSize: AetherIconSize.xl,
                        color: audioProvider.playMode != PlayMode.list
                            ? cfg.accent
                            : cfg.textSecondary,
                        selected: audioProvider.playMode != PlayMode.list,
                        tooltip: '播放模式',
                        onPressed: () => audioProvider.togglePlayMode(),
                      ),
                      AetherIconButton.transport(
                        icon: Icons.skip_previous,
                        color: cfg.textPrimary,
                        tooltip: '上一首',
                        onPressed: () => audioProvider.playPrevious(),
                      ),
                      AetherIconButton.play(
                        icon: audioProvider.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        tooltip: audioProvider.isPlaying ? '暂停' : '播放',
                        onPressed: () => audioProvider.playPause(),
                      ),
                      AetherIconButton.transport(
                        icon: Icons.skip_next,
                        color: cfg.textPrimary,
                        tooltip: '下一首',
                        onPressed: () => audioProvider.playNext(),
                      ),
                      AetherIconButton(
                        icon: audioProvider.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_up,
                        size: 40,
                        iconSize: AetherIconSize.xl,
                        color: audioProvider.volume == 0
                            ? cfg.textSecondary
                            : cfg.accent,
                        selected: audioProvider.volume > 0,
                        tooltip: '音量',
                        onPressed: () {
                          setState(() => showVolumeSlider = true);
                        },
                      ),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: AetherSpace.xxxl),
            ],
          ],
        ),
      ),
    );
  }
}
