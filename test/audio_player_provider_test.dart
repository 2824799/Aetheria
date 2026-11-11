import 'dart:async';
import 'dart:io';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/src/rust/audio/player.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlaybackApi extends Fake implements RustLibApi {
  var started = Completer<void>();
  var openGate = Completer<void>();
  final paths = <String>[];
  String? enginePath;

  void reset() {
    started = Completer<void>();
    openGate = Completer<void>();
    paths.clear();
    enginePath = null;
  }

  @override
  Future<void> crateApiPlaybackStartPlayback({
    required String path,
    required double volume,
    required double pitch,
    required String algo,
    required double normalizationGain,
  }) async {
    paths.add(path);
    if (!started.isCompleted) started.complete();
    await openGate.future;
    enginePath = path;
  }

  @override
  Future<void> crateApiPlaybackStopPlayback() async {
    enginePath = null;
  }

  @override
  Future<String> crateApiPlaybackGetDefaultOutputDeviceName() async => '';

  @override
  Future<PlaybackProgress> crateApiPlaybackGetPlaybackProgress() async =>
      const PlaybackProgress(positionSecs: 0, finished: false);
}

class _Audio extends AudioPlayerProvider {
  @override
  Future<void> loadSettings() async {}

  @override
  Future<void> refreshAudioOutputInfo() async {}
}

Song _song(String id, {String? filepath}) => Song(
  id: id,
  title: id,
  rating: 0,
  createdAt: '',
  tags: const [],
  versions: [
    AudioVersion(
      id: 'v-$id',
      songId: id,
      filepath: filepath ?? 'files/$id.wav',
      originalName: '$id.wav',
      duration: 180,
      fileSize: 10,
      isEnabled: true,
      isPrimary: true,
      metadataScanned: true,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PlaybackApi api;
  late _Audio audio;
  late Directory library;
  var disposed = false;

  setUpAll(() {
    api = _PlaybackApi();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api.reset();
    audio = _Audio();
    disposed = false;
    library = await Directory.systemTemp.createTemp('aetheria-player-test-');
    await Directory('${library.path}/files').create();
    for (final id in ['a', 'b', 'c']) {
      await File('${library.path}/files/$id.wav').writeAsBytes([0]);
    }
  });

  tearDown(() async {
    if (!api.openGate.isCompleted) api.openGate.complete();
    if (!disposed) audio.dispose();
    await Future<void>.delayed(Duration.zero);
    await library.delete(recursive: true);
  });

  test(
    'sync waits for an in-flight native open before releasing files',
    () async {
      final song = _song('a');
      final opening = audio.playSong(song, [song], library.path);
      await api.started.future;
      var stopped = false;
      final stopping = audio.stopForLibrarySync().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      api.openGate.complete();
      await opening;
      await stopping;
      expect(api.enginePath, isNull);
      expect(audio.playingSong, isNull);
      expect(audio.isPlaying, isFalse);
    },
  );

  test('dispose stops a stream that finishes opening afterwards', () async {
    final song = _song('a');
    final opening = audio.playSong(song, [song], library.path);
    await api.started.future;
    audio.dispose();
    disposed = true;
    api.openGate.complete();
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(api.enginePath, isNull);
  });

  test('rapid skips open only the newest queued song', () async {
    final songs = [_song('a'), _song('b'), _song('c')];
    final first = audio.playSong(songs[0], songs, library.path);
    await api.started.future;
    final second = audio.playSong(songs[1], songs, library.path);
    final third = audio.playSong(songs[2], songs, library.path);
    api.openGate.complete();
    await Future.wait([first, second, third]);
    expect(api.paths, [
      '${library.path}/files/a.wav',
      '${library.path}/files/c.wav',
    ]);
    expect(api.enginePath, '${library.path}/files/c.wav');
    expect(audio.playingSong?.id, 'c');
    expect(audio.isPlaying, isTrue);
  });

  test(
    'playback confines synced paths to the managed audio directory',
    () async {
      final song = _song('a', filepath: '../../a.wav');
      api.openGate.complete();
      await audio.playSong(song, [song], library.path);
      expect(api.enginePath, '${library.path}/files/a.wav');
    },
  );

  test('drive-relative filenames never reach the audio engine', () async {
    final song = _song('a', filepath: 'C:a.wav');
    await expectLater(
      audio.playSong(song, [song], library.path),
      throwsFormatException,
    );
    expect(api.paths, isEmpty);
    expect(audio.isPlaying, isFalse);
  });
}
