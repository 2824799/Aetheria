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

  test('reuses filtered results and invalidates them when filters change', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 1'), _song('2', 'Track 2')];
    final first = provider.displaySongs;
    expect(identical(provider.displaySongs, first), isTrue);
    expect(() => first.clear(), throwsUnsupportedError);
    provider.setSearchQuery('2');
    expect(provider.displaySongs.map((song) => song.id), ['2']);
    final filtered = provider.displaySongs;
    provider.setSearchQuery('2');
    expect(identical(filtered, provider.displaySongs), isTrue);
    provider.setSearchQuery('');
    expect(provider.displaySongs.map((song) => song.id), ['1', '2']);
    provider.dispose();
  });

  test('playlist filtering skips stale ids while preserving order', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 1'), _song('2', 'Track 2')]
      ..activePlaylistId = 'playlist'
      ..playlistSongIds = ['2', 'missing', '1'];
    expect(provider.displaySongs.map((song) => song.id), ['2', '1']);
    provider.setSearchQuery('1');
    expect(provider.displaySongs.map((song) => song.id), ['1']);
    provider.dispose();
  });

  test('preserves manually arranged playlist order', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 10'), _song('2', 'Track 2')]
      ..activePlaylistId = 'playlist'
      ..playlistSongIds = ['1', '2'];

    expect(provider.displaySongs.map((song) => song.id), ['1', '2']);
  });
}
