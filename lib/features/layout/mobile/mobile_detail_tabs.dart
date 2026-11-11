import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/player/ui/detail/song_tag_editor.dart';
import 'package:aetheria/features/player/ui/detail/version_list.dart';
import 'package:aetheria/features/player/ui/lyrics_panel.dart';
import 'package:aetheria/features/player/version_actions.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Body of one tab of the mobile song detail sheet.
class MobileDetailTab extends StatelessWidget {
  const MobileDetailTab({
    super.key,
    required this.tab,
    required this.song,
    required this.audio,
    required this.onOpenLyricManager,
    this.versionHeader,
  });

  final String tab;
  final Song song;
  final AudioPlayerProvider audio;
  final VoidCallback onOpenLyricManager;

  /// Shown above the version list.
  final Widget? versionHeader;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    switch (tab) {
      case 'versions':
        return SongVersionList(song: song, header: versionHeader);
      case 'tags':
        return SongTagEditor(song: song);
      case 'lyrics':
        return LyricsDisplayPanel(
          song: song,
          audioVersion: displayVersionForSong(song, audio),
          cfg: cfg,
          compact: true,
          onOpenManager: onOpenLyricManager,
        );
      case 'lyric_manager':
        return LyricsPanel(
          song: song,
          audioVersion: displayVersionForSong(song, audio),
          cfg: cfg,
          compact: true,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
