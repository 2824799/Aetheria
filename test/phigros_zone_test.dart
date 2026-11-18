import 'dart:io';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/settings/settings_playback_tab.dart';
import 'package:aetheria/features/phigros/ui/phigros_zone_header.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/features/sidebar/ui/sidebar.dart';
import 'package:aetheria/src/rust/audio/player.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

class _FakePhigrosApi extends Fake implements RustLibApi {
  final List<({String? chartPath, bool enabled, double volume, int offsetMs})>
  liveUpdates = [];
  final List<({String path, String? chartPath, bool enabled})> starts = [];
  final List<(String songId, String diff)> diffUpdates = [];
  final List<(String songId, String mode, double? vol, int? offset)>
  songHitsoundUpdates = [];
  String? seDirConfigured;

  @override
  Future<void> crateApiPlaybackConfigureHitsoundBank({String? seDir}) async {
    seDirConfigured = seDir;
  }

  @override
  Future<void> crateApiPlaybackUpdatePlaybackHitsound({
    String? chartPath,
    required bool enabled,
    required double volume,
    required int offsetMs,
  }) async {
    liveUpdates.add((
      chartPath: chartPath,
      enabled: enabled,
      volume: volume,
      offsetMs: offsetMs,
    ));
  }

  @override
  Future<void> crateApiPlaybackStartPlayback({
    required String path,
    required double volume,
    required double pitch,
    required String algo,
    required double normalizationGain,
    String? chartPath,
    required bool hitsoundEnabled,
    required double hitsoundVolume,
    required int hitsoundOffsetMs,
  }) async {
    starts.add((path: path, chartPath: chartPath, enabled: hitsoundEnabled));
  }

  @override
  Future<void> crateApiPlaybackStopPlayback() async {}

  @override
  Future<void> crateApiPlaybackSetVolume({required double volume}) async {}

  @override
  Future<void> crateApiPlaybackSetPitch({
    required double pitch,
    required String algo,
  }) async {}

  @override
  Future<void> crateApiPlaybackSetOutputBufferMs({required int ms}) async {}

  @override
  Future<void> crateApiPlaybackSetOutputLatencyMode({
    required String mode,
  }) async {}

  @override
  Future<void> crateApiPlaybackSetAudioQualitySettings({
    required bool peakProtectionEnabled,
    required bool ditherEnabled,
    required String rubberbandWindow,
    required bool rubberbandFormantPreserved,
    required bool rubberbandVocalOnlyPitch,
    required String resamplerQuality,
  }) async {}

  @override
  void crateApiPlaybackSetAudioPerformanceProfilingEnabled({
    required bool enabled,
  }) {}

  @override
  Future<AudioOutputInfo> crateApiPlaybackGetAudioOutputInfo() async =>
      AudioOutputInfo(
        deviceName: 'Test',
        sampleRate: 44100,
        channels: 2,
        sampleFormat: 'f32',
        bufferSize: 'Default',
        outputLatencyMode: 'shared-default',
        outputBufferMs: 240,
        queuedMs: 0,
        underruns: BigInt.zero,
        clippedSamples: BigInt.zero,
        peakDb: -60,
      );

  @override
  Future<String> crateApiPlaybackGetDefaultOutputDeviceName() async => 'Test';

  @override
  Future<PlaybackProgress> crateApiPlaybackGetPlaybackProgress() async =>
      const PlaybackProgress(positionSecs: 0, playbackRate: 1.0, finished: false);

  @override
  Future<void> crateApiMusicSetPhigrosSongDifficulty({
    required String songId,
    required String difficulty,
  }) async {
    diffUpdates.add((songId, difficulty));
  }

  @override
  Future<void> crateApiMusicSetPhigrosSongHitsound({
    required String songId,
    required String mode,
    double? volume,
    int? offsetMs,
  }) async {
    songHitsoundUpdates.add((songId, mode, volume, offsetMs));
  }

  @override
  Future<void> crateApiMusicCheckpointLibraryDatabase() async {}

  @override
  bool crateApiMusicIsLibraryInitialized() => true;

  @override
  Future<List<Song>> crateApiMusicGetSongs() async => const [];

  @override
  Future<List<Tag>> crateApiMusicGetTags() async => const [];

  @override
  Future<List<Playlist>> crateApiMusicGetPlaylists() async => const [];

  @override
  Future<String> crateApiMusicGetLibraryPath() async => '';

  @override
  Future<List<String>> crateApiMusicGetSongIdsWithLyrics() async => const [];

  @override
  Future<List<String>> crateApiMusicGetPlaylistSongs({
    required String playlistId,
  }) async => const [];
}

Song _phigrosSong({
  String id = 'phi-1',
  String title = 'Igallta',
  String chapter = '第六章 · 方舟蜃景',
  String selectedDifficulty = 'IN',
  String hitsoundMode = 'global',
  double? hitsoundVolume,
  int? hitsoundOffsetMs,
  String? audioInOverride,
}) {
  return Song(
    id: id,
    title: title,
    artist: 'Se-U-Ra',
    album: chapter,
    rating: 0,
    createdAt: '',
    tags: const [],
    versions: [
      AudioVersion(
        id: 'ver-$id',
        songId: id,
        filepath: 'files/phi_$id.flac',
        originalName: '$title.flac',
        duration: 122.0,
        fileSize: 1024,
        isEnabled: true,
        isPrimary: true,
        metadataScanned: true,
      ),
    ],
    phigros: PhigrosSongMeta(
      phigrosId: '$title.SeURa.0',
      chapter: chapter,
      composer: 'Se-U-Ra',
      illustrator: 'L-seven',
      selectedDifficulty: selectedDifficulty,
      hitsoundMode: hitsoundMode,
      hitsoundVolume: hitsoundVolume,
      hitsoundOffsetMs: hitsoundOffsetMs,
      charts: [
        PhigrosChartMeta(
          difficulty: 'EZ',
          sortRank: 0,
          rating: 7.0,
          charter: 'Tester EZ',
          bpmMin: 160,
          bpmMax: 230,
          chartOffsetMs: 0,
          noteCount: 414,
          tapCount: 250,
          dragCount: 90,
          holdCount: 50,
          flickCount: 24,
          chartRelPath: 'phigros/charts/${id}_EZ.json',
        ),
        PhigrosChartMeta(
          difficulty: 'IN',
          sortRank: 2,
          rating: 15.9,
          charter: 'XMT',
          bpmMin: 160,
          bpmMax: 230,
          chartOffsetMs: 12,
          noteCount: 1018,
          tapCount: 680,
          dragCount: 140,
          holdCount: 110,
          flickCount: 88,
          audioRelPath: audioInOverride,
          chartRelPath: 'phigros/charts/${id}_IN.json',
        ),
        PhigrosChartMeta(
          difficulty: 'AT',
          sortRank: 3,
          rating: 16.7,
          charter: 'Barbarianerman',
          bpmMin: 160,
          bpmMax: 230,
          chartOffsetMs: 12,
          noteCount: 1114,
          tapCount: 801,
          dragCount: 121,
          holdCount: 115,
          flickCount: 77,
          chartRelPath: 'phigros/charts/${id}_AT.json',
        ),
      ],
    ),
  );
}

class _MutableLibrary extends TestLibrary {
  final _FakePhigrosApi api;
  _MutableLibrary(this.api);

  @override
  Future<Song?> setPhigrosDifficulty(String songId, String difficulty) async {
    await api.crateApiMusicSetPhigrosSongDifficulty(
      songId: songId,
      difficulty: difficulty,
    );
    songs = [
      for (final s in songs)
        if (s.id == songId && s.phigros != null)
          Song(
            id: s.id,
            title: s.title,
            artist: s.artist,
            album: s.album,
            lyrics: s.lyrics,
            coverPath: s.coverPath,
            rating: s.rating,
            createdAt: s.createdAt,
            versions: s.versions,
            tags: s.tags,
            phigros: PhigrosSongMeta(
              phigrosId: s.phigros!.phigrosId,
              chapter: s.phigros!.chapter,
              composer: s.phigros!.composer,
              illustrator: s.phigros!.illustrator,
              selectedDifficulty: difficulty,
              hitsoundMode: s.phigros!.hitsoundMode,
              hitsoundVolume: s.phigros!.hitsoundVolume,
              hitsoundOffsetMs: s.phigros!.hitsoundOffsetMs,
              charts: s.phigros!.charts,
            ),
          )
        else
          s,
    ];
    notifyListeners();
    return songs.where((s) => s.id == songId).firstOrNull;
  }

  @override
  Future<Song?> setPhigrosSongHitsound(
    String songId, {
    required String mode,
    double? volume,
    int? offsetMs,
  }) async {
    await api.crateApiMusicSetPhigrosSongHitsound(
      songId: songId,
      mode: mode,
      volume: volume,
      offsetMs: offsetMs,
    );
    songs = [
      for (final s in songs)
        if (s.id == songId && s.phigros != null)
          Song(
            id: s.id,
            title: s.title,
            artist: s.artist,
            album: s.album,
            lyrics: s.lyrics,
            coverPath: s.coverPath,
            rating: s.rating,
            createdAt: s.createdAt,
            versions: s.versions,
            tags: s.tags,
            phigros: PhigrosSongMeta(
              phigrosId: s.phigros!.phigrosId,
              chapter: s.phigros!.chapter,
              composer: s.phigros!.composer,
              illustrator: s.phigros!.illustrator,
              selectedDifficulty: s.phigros!.selectedDifficulty,
              hitsoundMode: mode,
              hitsoundVolume: volume,
              hitsoundOffsetMs: offsetMs,
              charts: s.phigros!.charts,
            ),
          )
        else
          s,
    ];
    notifyListeners();
    return songs.where((s) => s.id == songId).firstOrNull;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePhigrosApi api;

  setUpAll(() {
    api = _FakePhigrosApi();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api.liveUpdates.clear();
    api.starts.clear();
    api.diffUpdates.clear();
    api.songHitsoundUpdates.clear();
  });

  test('AudioPlayerProvider resolves global vs per-song hitsound overrides and switches live', () async {
    final dir = await Directory.systemTemp.createTemp('aetheria-phi-test-');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/files').create(recursive: true);
    await File('${dir.path}/files/phi_phi-1.flac').writeAsBytes([1, 2, 3]);

    final audio = AudioPlayerProvider();
    addTearDown(audio.dispose);
    await audio.loadSettings();

    final song = _phigrosSong();
    await audio.playSong(song, [song], dir.path);
    expect(api.seDirConfigured, '${dir.path.replaceAll('\\', '/')}/phigros/se');
    expect(api.starts.single.enabled, isTrue);
    expect(api.starts.single.chartPath, '${dir.path.replaceAll('\\', '/')}/phigros/charts/phi-1_IN.json');

    // Global changes push live
    await audio.setPhigrosHitsoundEnabled(false);
    expect(api.liveUpdates.last.enabled, isFalse);
    await audio.setPhigrosHitsoundVolume(1.2);
    expect(api.liveUpdates.last.volume, closeTo(1.2, 1e-6));
    await audio.setPhigrosHitsoundOffsetMs(-25);
    expect(api.liveUpdates.last.offsetMs, -25);

    // Per-song override turns hitsound ON despite global OFF and changes chart difficulty live
    final overridden = _phigrosSong(
      selectedDifficulty: 'AT',
      hitsoundMode: 'on',
      hitsoundVolume: 0.45,
      hitsoundOffsetMs: 15,
    );
    audio.syncSongSnapshot(overridden);
    await Future<void>.delayed(Duration.zero);

    expect(api.liveUpdates.last.enabled, isTrue);
    expect(api.liveUpdates.last.volume, closeTo(0.45, 1e-6));
    expect(api.liveUpdates.last.offsetMs, 15);
    expect(api.liveUpdates.last.chartPath, '${dir.path.replaceAll('\\', '/')}/phigros/charts/phi-1_AT.json');
    expect(api.starts.length, 1); // No playback interruption when audio file unchanged
  });

  test('LibraryProvider Phigros zone playlist filters chapters cleanly while keeping songs in All Songs', () async {
    final normal = testSong('n1');
    final phi1 = _phigrosSong(id: 'p1', title: 'Igallta', chapter: '第六章 · 方舟蜃景');
    final phi2 = _phigrosSong(id: 'p2', title: 'Glaciaxion', chapter: '过去的章节 (Legacy)');

    final library = TestLibrary()
      ..songs = [normal, phi1, phi2]
      ..playlists = const [
        Playlist(id: 'pl-phi', name: 'Phigros', createdAt: '', kind: 'phigros'),
        Playlist(id: 'pl-fav', name: '日常', createdAt: '', kind: 'normal'),
      ];
    addTearDown(library.dispose);

    // All songs shows normal + Phigros tracks together
    expect(library.displaySongs.map((s) => s.id), containsAll(['n1', 'p1', 'p2']));

    library.activePlaylistId = 'pl-phi';
    library.playlistSongIds = ['p1', 'p2'];
    library.notifyListeners();
    expect(library.isPhigrosPlaylistActive, isTrue);
    expect(library.phigrosChapters, ['第六章 · 方舟蜃景', '过去的章节 (Legacy)']);
    expect(library.displaySongs.map((s) => s.id), ['p1', 'p2']);

    library.setActivePhigrosChapter('过去的章节 (Legacy)');
    expect(library.displaySongs.map((s) => s.id), ['p2']);
  });

  testWidgets('Sidebar, PhigrosZoneHeader, DetailPane, and SettingsPlaybackTab integrate cleanly', (
    tester,
  ) async {
    final normal = testSong('n1');
    final phiSong = _phigrosSong(id: 'p1');
    final library = _MutableLibrary(api)
      ..songs = [normal, phiSong]
      ..playlists = const [
        Playlist(id: 'pl-phi', name: 'Phigros', createdAt: '', kind: 'phigros'),
        Playlist(id: 'pl-fav', name: '收藏', createdAt: '', kind: 'normal'),
      ]
      ..isLoading = false;
    library.activePlaylistId = 'pl-phi';
    library.playlistSongIds = ['p1'];
    addTearDown(library.dispose);

    final audio = AudioPlayerProvider()..setActiveSong(phiSong);
    addTearDown(audio.dispose);
    final theme = UIThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: Scaffold(
            body: Row(
              children: [
                const Sidebar(width: 220),
                const Expanded(
                  child: Column(
                    children: [
                      PhigrosZoneHeader(),
                      Expanded(child: DetailPane()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sidebar separates Phigros zone from regular playlists without duplication
    expect(find.text('Phigros 专区'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);

    // Zone header shows global toggle + chapter chips
    expect(find.text('全局打击音效'), findsOneWidget);
    expect(find.text('全部章节'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PhigrosZoneHeader),
        matching: find.text('第六章 · 方舟蜃景'),
      ),
      findsOneWidget,
    );

    // DetailPane shows Phigros tab + switches difficulty cleanly
    expect(find.text('谱面与音效'), findsOneWidget);
    expect(find.text('Lv.16.7'), findsOneWidget);
    await tester.tap(find.text('Lv.16.7'));
    await tester.pumpAndSettle();
    expect(api.diffUpdates.last, ('p1', 'AT'));

    // Per-song hitsound override
    await tester.ensureVisible(find.text('单独关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单独关闭'));
    await tester.pumpAndSettle();
    expect(api.songHitsoundUpdates.last.$2, 'off');

    // Global settings section in SettingsPlaybackTab renders safely
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsPlaybackTab(
                cfg: theme.currentTheme,
                audioProvider: audio,
                isDesktop: true,
                onShowCustomBufferDialog: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phigros 打击音效（全局默认）'), findsOneWidget);
  });
}
