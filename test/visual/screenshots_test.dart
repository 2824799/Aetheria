// Renders the main screens to PNG files so layout and colour changes can be
// reviewed without launching the app.
//
//   AETHERIA_SHOTS=/tmp/aetheria-shots flutter test test/visual/screenshots_test.dart
//
// Skipped unless AETHERIA_SHOTS is set, so a normal `flutter test` is unaffected.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';
import 'package:aetheria/features/player/ui/song_cover_art.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/ui_test_fakes.dart';

final String? _outDir = Platform.environment['AETHERIA_SHOTS'];

const _tags = [
  Tag(id: 1, name: '华语', color: '#3B82F6', category: '语种'),
  Tag(id: 2, name: '日语', color: '#F472B6', category: '语种'),
  Tag(id: 3, name: '英语', color: '#34D399', category: '语种'),
  Tag(id: 4, name: '摇滚', color: '#F97316', category: '流派'),
  Tag(id: 5, name: '民谣', color: '#A78BFA', category: '流派'),
  Tag(id: 6, name: '电子', color: '#22D3EE', category: '流派'),
  Tag(id: 7, name: '深夜', color: '#64748B', category: '场景'),
  Tag(id: 8, name: '通勤', color: '#FBBF24', category: '场景'),
];

const _tracks = [
  ('晴天', '周杰伦', '叶惠美'),
  ('夜に駆ける', 'YOASOBI', 'THE BOOK'),
  ('Blinding Lights', 'The Weeknd', 'After Hours'),
  ('平凡之路', '朴树', '猎户星座'),
  ('Lemon', '米津玄師', 'STRAY SHEEP'),
  ('海阔天空', 'Beyond', '乐与怒'),
  ('Shape of You', 'Ed Sheeran', '÷'),
  ('起风了', '买辣椒也用券', '起风了'),
  ('打上花火', 'DAOKO × 米津玄師', 'THANK YOU BLUE'),
  ('Viva La Vida', 'Coldplay', 'Viva la Vida or Death and All His Friends'),
  ('后来', '刘若英', '我等你'),
  ('群青', 'YOASOBI', 'THE BOOK'),
  ('Bohemian Rhapsody', 'Queen', 'A Night at the Opera'),
  ('成都', '赵雷', '无法长大'),
  ('残酷な天使のテーゼ', '高橋洋子', 'NEON GENESIS EVANGELION'),
  ('七里香', '周杰伦', '七里香'),
  ('Get Lucky', 'Daft Punk', 'Random Access Memories'),
  ('南山南', '马頔', '孤岛'),
  ('千本桜', '黒うさP feat. 初音ミク', 'ALL THAT 千本桜!!'),
  ('Hotel California', 'Eagles', 'Hotel California'),
  ('这是一首标题特别特别特别长的歌用来测试省略号是否正常工作', '一位名字也很长很长的歌手与他的朋友们', '专辑'),
  ('稻香', '周杰伦', '魔杰座'),
];

List<Song> _songs() {
  return [
    for (var i = 0; i < _tracks.length; i++)
      Song(
        id: 's$i',
        title: _tracks[i].$1,
        artist: i == 13 ? null : _tracks[i].$2,
        album: _tracks[i].$3,
        rating: 0,
        createdAt: '2026-01-01',
        versions: [
          AudioVersion(
            id: 'v$i-0',
            songId: 's$i',
            filepath: 'files/$i.flac',
            originalName: '${_tracks[i].$1}.flac',
            format: i % 3 == 0 ? 'FLAC' : (i % 3 == 1 ? 'MP3' : 'WAV'),
            bitrate: i % 3 == 1 ? (i % 2 == 0 ? 128000 : 320000) : 1411000,
            sampleRate: i % 5 == 0 ? 96000 : 44100,
            duration: 180.0 + i * 7,
            fileSize: 32000000 + i * 100000,
            isEnabled: true,
            isPrimary: true,
            bitDepth: i % 5 == 0 ? 24 : 16,
            loudness: -9.5 - i * 0.2,
            metadataScanned: true,
          ),
          if (i % 4 == 0)
            AudioVersion(
              id: 'v$i-1',
              songId: 's$i',
              filepath: 'files/$i.mp3',
              originalName: '${_tracks[i].$1} (Live).mp3',
              format: 'MP3',
              bitrate: 320000,
              sampleRate: 44100,
              duration: 200.0 + i * 7,
              fileSize: 9000000,
              isEnabled: true,
              isPrimary: false,
              bitDepth: 16,
              loudness: -11.0,
              metadataScanned: true,
            ),
        ],
        tags: [
          _tags[i % 3],
          if (i % 2 == 0) _tags[3 + i % 3],
          if (i % 5 == 0) _tags[6 + i % 2],
        ],
      ),
  ];
}

class _ShotLibrary extends TestLibrary {
  @override
  Future<void> setActivePlaylist(String? playlistId) async {
    activePlaylistId = playlistId;
    notifyListeners();
  }
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final icons = FontLoader('MaterialIcons')
    ..addFont(
      read(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await icons.load();

  final home = Platform.environment['HOME'] ?? '';
  final candidates = [
    Platform.environment['AETHERIA_SHOT_FONT'],
    '$home/.fonts/winfonts/system/NotoSansSC-VF.ttf',
    '/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.ttc',
  ].whereType<String>().where((path) => File(path).existsSync());
  if (candidates.isEmpty) return;
  final text = FontLoader('Roboto')..addFont(read(candidates.first));
  await text.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$_outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class _Scene {
  _Scene(this.themeType) {
    library
      ..songs = _songs()
      ..tags = _tags
      ..playlists = const [
        Playlist(id: 'p1', name: '通勤路上', createdAt: ''),
        Playlist(id: 'p2', name: '深夜循环', createdAt: ''),
        Playlist(id: 'p3', name: 'J-POP 精选', createdAt: ''),
      ]
      ..songIdsWithLyrics = {'s0', 's1', 's4', 's7'}
      ..isLoading = false;
    audio
      ..playingSong = library.songs[1]
      ..activeSong = library.songs[1]
      ..playingVersion = library.songs[1].versions.first
      ..isPlaying = true
      ..totalDuration = const Duration(minutes: 4, seconds: 21);
    audio.positionListenable.value = const Duration(minutes: 1, seconds: 37);
  }

  final AppThemeType themeType;
  final library = _ShotLibrary();
  final audio = TestAudio();
  final sync = TestSync();
  final theme = UIThemeProvider();
  final floating = FloatingLyricsProvider();

  Future<void> pump(WidgetTester tester, Size size) async {
    // MainLayout picks mobile or desktop from MediaQuery, which follows the
    // view size rather than the surface size.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await theme.setTheme(themeType);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<FloatingLyricsProvider>.value(value: floating),
        ],
        child: RepaintBoundary(
          key: const ValueKey('shot-root'),
          child: Consumer<UIThemeProvider>(
            builder: (context, theme, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.themeData,
              home: const MainLayout(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    sync.dispose();
    theme.dispose();
    floating.dispose();
  }
}

void main() {
  if (_outDir == null) {
    test('screenshots are skipped without AETHERIA_SHOTS', () {}, skip: true);
    return;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  const desktop = Size(1440, 900);
  const mobile = Size(412, 892);

  for (final type in AppThemeType.values) {
    final label = type.name;

    testWidgets('desktop library ($label)', (tester) async {
      final scene = _Scene(type);
      await scene.pump(tester, desktop);
      await _shoot(tester, 'desktop-library-$label');
      await scene.close(tester);
    });

    testWidgets('mobile library ($label)', (tester) async {
      final scene = _Scene(type);
      await scene.pump(tester, mobile);
      await _shoot(tester, 'mobile-library-$label');
      await scene.close(tester);
    });
  }

  for (final tab in ['versions', 'tags', 'lyrics', 'lyric_manager']) {
    testWidgets('desktop detail drawer ($tab)', (tester) async {
      final scene = _Scene(
        tab == 'tags' ? AppThemeType.light : AppThemeType.dark,
      );
      scene.audio
        ..activeSong = scene.library.songs[0]
        ..activeTab = tab;
      await scene.pump(tester, desktop);
      scene.audio.setDetailOpen(true);
      await tester.pumpAndSettle();
      await _shoot(tester, 'desktop-detail-$tab');
      await scene.close(tester);
    });
  }

  testWidgets('desktop settings', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, desktop);
    SettingsModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await _shoot(tester, 'desktop-settings-dark');
    await scene.close(tester);
  });

  testWidgets('desktop tag manager', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, desktop);
    TagManagerModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await _shoot(tester, 'desktop-tags-dark');
    await scene.close(tester);
  });

  testWidgets('desktop empty library', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    scene.library
      ..songs = []
      ..playlists = [];
    scene.audio
      ..playingSong = null
      ..activeSong = null
      ..isPlaying = false;
    await scene.pump(tester, desktop);
    await _shoot(tester, 'desktop-empty-dark');
    await scene.close(tester);
  });

  testWidgets('mobile drawer', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, mobile);
    await tester.tap(find.byTooltip('歌单'));
    await tester.pumpAndSettle();
    await _shoot(tester, 'mobile-drawer-dark');
    await scene.close(tester);
  });

  testWidgets('mobile song menu', (tester) async {
    final scene = _Scene(AppThemeType.light);
    await scene.pump(tester, mobile);
    await tester.longPress(find.text('Blinding Lights'));
    await tester.pumpAndSettle();
    await _shoot(tester, 'mobile-menu-light');
    await scene.close(tester);
  });

  // The sheet keeps its own tab; switch by tapping the tab label.
  for (final (tab, label) in [('versions', '音源 ('), ('tags', '标签 (')]) {
    testWidgets('mobile detail sheet ($tab)', (tester) async {
      final scene = _Scene(AppThemeType.dark);
      await scene.pump(tester, mobile);
      await tester.tap(find.byType(SongCoverArt).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(label));
      await tester.pumpAndSettle();
      await _shoot(tester, 'mobile-detail-$tab');
      await scene.close(tester);
    });
  }

  testWidgets('mobile settings', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, mobile);
    SettingsModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await _shoot(tester, 'mobile-settings-dark');
    await scene.close(tester);
  });

  testWidgets('mobile settings page', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, mobile);
    SettingsModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await _shoot(tester, 'mobile-settings-theme-dark');
    await scene.close(tester);
  });

  testWidgets('desktop tag manager editing (light)', (tester) async {
    final scene = _Scene(AppThemeType.light);
    await scene.pump(tester, desktop);
    TagManagerModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(TagManagerModal),
        matching: find.text('摇滚'),
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'desktop-tags-edit-light');
    await scene.close(tester);
  });

  testWidgets('mobile tag manager', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    await scene.pump(tester, mobile);
    TagManagerModal.show(tester.element(find.byType(MainLayout)));
    await tester.pumpAndSettle();
    await _shoot(tester, 'mobile-tags-dark');
    await scene.close(tester);
  });

  testWidgets('mobile empty filter result', (tester) async {
    final scene = _Scene(AppThemeType.dark);
    scene.library.searchQuery = '不存在的歌';
    await scene.pump(tester, mobile);
    await _shoot(tester, 'mobile-nomatch-dark');
    await scene.close(tester);
  });
}
