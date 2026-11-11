import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Saves a new title and/or artist for [song] and refreshes the copy held by
/// the player, so the play bar shows the new text straight away.
///
/// Does nothing when the values are unchanged. Throws when the title is empty
/// or the library rejects the change.
Future<void> saveSongMetadata(
  BuildContext context,
  Song song, {
  String? title,
  String? artist,
}) async {
  final nextTitle = (title ?? song.title).trim();
  final nextArtist = (artist ?? song.artist ?? '').trim();
  if (nextTitle.isEmpty) {
    throw Exception('歌曲名称不能为空');
  }
  if (nextTitle == song.title && nextArtist == (song.artist ?? '')) {
    return;
  }

  final library = context.read<LibraryProvider>();
  final audio = context.read<AudioPlayerProvider>();
  await library.updateSongMetadata(song.id, nextTitle, nextArtist);
  for (final updated in library.songs) {
    if (updated.id == song.id) {
      audio.syncSongSnapshot(updated);
      break;
    }
  }
}
