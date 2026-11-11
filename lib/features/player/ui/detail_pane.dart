import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_tabs.dart';
import 'package:aetheria/features/player/song_metadata.dart';
import 'package:aetheria/features/player/ui/detail/editable_metadata_text.dart';
import 'package:aetheria/features/player/ui/detail/song_tag_editor.dart';
import 'package:aetheria/features/player/ui/detail/version_list.dart';
import 'package:aetheria/features/player/ui/lyrics_panel.dart';
import 'package:aetheria/features/player/ui/song_cover_art.dart';
import 'package:aetheria/features/player/version_actions.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Desktop drawer for the selected song: lyrics, tags and audio versions.
class DetailPane extends StatelessWidget {
  const DetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.read<AudioPlayerProvider>();
    // Rebuild for the fields this pane shows, not for every position tick.
    final state = context
        .select<
          AudioPlayerProvider,
          ({Song? activeSong, String? playingId, AudioVersion? version, String tab})
        >(
          (audio) => (
            activeSong: audio.activeSong,
            playingId: audio.playingSong?.id,
            version: audio.playingVersion,
            tab: audio.activeTab,
          ),
        );
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;

    final activeSong = state.activeSong;
    if (activeSong == null) {
      return const SizedBox.shrink();
    }
    // Prefer the library's copy: it carries edits made since selection.
    var song = activeSong;
    for (final candidate in library.songs) {
      if (candidate.id == activeSong.id) {
        song = candidate;
        break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: cfg.bgElevated,
        border: Border(left: BorderSide(color: cfg.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: cfg.scrim.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(-12, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _Header(song: song, onClose: () => audio.setDetailOpen(false)),
          AetherTabBar(
            value: state.tab,
            onChanged: audio.setActiveTab,
            tabs: const [
              AetherTabItem(id: 'lyrics', label: '滚动歌词'),
              AetherTabItem(id: 'lyric_manager', label: '歌词管理'),
              AetherTabItem(id: 'tags', label: '标签'),
              AetherTabItem(id: 'versions', label: '音源版本'),
            ],
          ),
          Divider(height: 1, color: cfg.borderSubtle),
          Expanded(child: _buildTab(state.tab, song, audio, cfg)),
        ],
      ),
    );
  }

  Widget _buildTab(
    String tab,
    Song song,
    AudioPlayerProvider audio,
    AppThemeConfig cfg,
  ) {
    switch (tab) {
      case 'lyrics':
        return LyricsDisplayPanel(
          song: song,
          audioVersion: displayVersionForSong(song, audio),
          cfg: cfg,
        );
      case 'lyric_manager':
        return LyricsPanel(
          song: song,
          audioVersion: displayVersionForSong(song, audio),
          cfg: cfg,
        );
      case 'tags':
        return SongTagEditor(song: song);
      case 'versions':
        return SongVersionList(song: song);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Cover, editable title and artist, and the close button.
class _Header extends StatelessWidget {
  const _Header({required this.song, required this.onClose});

  final Song song;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.xl,
        AetherSpace.md,
        AetherSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SongCoverArt(
            song: song,
            cfg: cfg,
            size: 56,
            borderRadius: AetherRadius.md,
            iconSize: AetherIconSize.xxl,
            shadow: false,
          ),
          const SizedBox(width: AetherSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AetherSpace.xs),
                EditableMetadataText(
                  value: song.title,
                  emptyText: '未命名歌曲',
                  tooltip: '点击修改歌曲名称',
                  style: AetherType.titleStyle(cfg.textPrimary),
                  onSave: (value) =>
                      saveSongMetadata(context, song, title: value),
                ),
                EditableMetadataText(
                  value: song.artist ?? '',
                  emptyText: '未知歌手',
                  tooltip: '点击修改歌手',
                  style: AetherType.bodySmStyle(cfg.textSecondary),
                  onSave: (value) =>
                      saveSongMetadata(context, song, artist: value),
                ),
              ],
            ),
          ),
          AetherIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭详情',
            size: 32,
            iconSize: AetherIconSize.lg,
            color: cfg.textSecondary,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
