import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_sheet.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_detail_sheet.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Plays [song] within the list on screen; a failure opens a dialog with the
/// full reason, which is long enough to need selecting and copying.
Future<void> mobilePlaySong(
  BuildContext context,
  Song song,
  LibraryProvider library,
  AudioPlayerProvider audio,
) async {
  audio.setActiveSong(song);
  try {
    await audio.playSong(song, library.displaySongs, library.libraryPath);
  } catch (e) {
    if (!context.mounted) return;
    await showAetherDialog<void>(
      context: context,
      builder: (ctx) => AetherDialog(
        title: '播放失败',
        content: SelectableText(
          e.toString(),
          style: AetherType.bodySmStyle(ctx.tokens.textSecondary),
        ),
        actions: [
          AetherButton.primary(
            label: '关闭',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

/// Opens the full-height detail sheet for [song].
void mobileOpenSongDetail(
  BuildContext context,
  Song song,
  AudioPlayerProvider audio,
) {
  audio.setActiveSong(song);
  showAetherSheet<void>(
    context: context,
    isScrollControlled: true,
    decorate: false,
    maxHeightFactor: 0.95,
    builder: (_) => MobileSongDetailSheet(initialSong: song),
  );
}
