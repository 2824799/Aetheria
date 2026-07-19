import 'package:flutter_test/flutter_test.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';

Song _song(String id, String title, {String? artist}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    rating: 0,
    createdAt: '',
    versions: const [],
    tags: const [],
  );
}

void main() {
  test('uses Explorer-style natural ordering for non-playlist song lists', () {
    final provider = LibraryProvider()
      ..songs = [
        _song('4', 'Track 10'),
        _song('1', 'Track 2'),
        _song('3', 'Track 02'),
        _song('2', 'track 1'),
        _song('6', 'Same title', artist: 'Artist 10'),
        _song('5', 'Same Title', artist: 'Artist 2'),
      ];

    expect(provider.displaySongs.map((song) => song.id), [
      '5',
      '6',
      '2',
      '1',
      '3',
      '4',
    ]);
  });

  test('preserves manually arranged playlist order', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 10'), _song('2', 'Track 2')]
      ..activePlaylistId = 'playlist'
      ..playlistSongIds = ['1', '2'];

    expect(provider.displaySongs.map((song) => song.id), ['1', '2']);
  });
}
