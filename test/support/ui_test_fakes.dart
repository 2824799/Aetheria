import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/foundation.dart';

Song testSong(String id) => Song(
  id: id,
  title: 'Track $id',
  rating: 0,
  createdAt: '',
  versions: const [],
  tags: const [],
);

class TestLibrary extends LibraryProvider {
  int displayReads = 0;
  @override
  Future<void> loadLibrary() async {
    isLoading = false;
    notifyListeners();
  }

  @override
  List<Song> get displaySongs {
    displayReads++;
    return super.displaySongs;
  }

  @override
  Future<String?> ensureSongCover(Song song) async => null;
}

class TestAudio extends ChangeNotifier implements AudioPlayerProvider {
  @override
  final ValueNotifier<Duration> positionListenable = ValueNotifier(
    Duration.zero,
  );
  @override
  Duration get currentPosition => positionListenable.value;
  @override
  Duration totalDuration = const Duration(minutes: 2);
  @override
  Song? playingSong;
  @override
  Song? activeSong;
  @override
  bool isPlaying = false;
  @override
  bool isDetailOpen = false;
  @override
  double volume = 0.8;
  @override
  PlayMode playMode = PlayMode.list;
  @override
  void setDetailOpen(bool value) {
    isDetailOpen = value;
    notifyListeners();
  }

  @override
  Future<void> restorePlaybackState(
    List<Song> songs,
    String path, {
    int? audioServerPort,
  }) async {}
  int nextCalls = 0;
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    positionListenable.value = value;
  }

  @override
  void playNext() {
    nextCalls++;
  }

  @override
  Future<void> playPause() async {}
  @override
  void playPrevious() {}
  @override
  void togglePlayMode() {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  void dispose() {
    positionListenable.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSync extends ChangeNotifier implements SyncProvider {
  @override
  IncomingSyncRequest? get incomingRequest => null;
  @override
  Future<void> start(LibraryProvider libraryProvider) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
