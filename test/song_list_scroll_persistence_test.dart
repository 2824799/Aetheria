import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

class _ScrollTestApi extends Fake implements RustLibApi {
  final List<Song> dbSongs = [];
  final List<Playlist> dbPlaylists = [];
  final Map<String, List<String>> dbPlaylistSongs = {};

  void reset() {
    dbSongs.clear();
    dbPlaylists.clear();
    dbPlaylistSongs.clear();
  }

  @override
  bool crateApiMusicIsLibraryInitialized() => true;

  @override
  Future<List<Song>> crateApiMusicGetSongs() async => List<Song>.of(dbSongs);

  @override
  Future<List<Tag>> crateApiMusicGetTags() async => const [
    Tag(id: 1, name: 'Tagged'),
  ];

  @override
  Future<List<Playlist>> crateApiMusicGetPlaylists() async =>
      List<Playlist>.of(dbPlaylists);

  @override
  Future<String> crateApiMusicGetLibraryPath() async => '/tmp/aetheria-scroll';

  @override
  Future<List<String>> crateApiMusicGetSongIdsWithLyrics() async => const [];

  @override
  Future<List<String>> crateApiMusicGetPlaylistSongs({
    required String playlistId,
  }) async => List<String>.of(dbPlaylistSongs[playlistId] ?? const []);
}

Song _song(String id, {List<Tag> tags = const []}) => Song(
  id: id,
  title: 'Song $id',
  artist: 'Artist $id',
  rating: 0,
  createdAt: '',
  versions: const [],
  tags: tags,
);

Future<
  ({
    LibraryProvider library,
    TestAudio audio,
    UIThemeProvider theme,
    TestSync sync,
  })
>
_mountMainLayout(WidgetTester tester) async {
  final library = LibraryProvider();
  final audio = TestAudio();
  final theme = UIThemeProvider();
  final sync = TestSync();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
        ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ChangeNotifierProvider<SyncProvider>.value(value: sync),
      ],
      child: MaterialApp(theme: theme.themeData, home: const MainLayout()),
    ),
  );
  await tester.pumpAndSettle();
  return (library: library, audio: audio, theme: theme, sync: sync);
}

Future<void> _unmountSession(
  WidgetTester tester,
  ({
    LibraryProvider library,
    TestAudio audio,
    UIThemeProvider theme,
    TestSync sync,
  })
  session,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  session.library.dispose();
  session.audio.dispose();
  session.theme.dispose();
  session.sync.dispose();
}

ScrollController _desktopSongListController(WidgetTester tester) {
  final list = find.descendant(
    of: find.byType(SongTable),
    matching: find.byType(ListView),
  );
  return tester.widget<ListView>(list).controller!;
}

ScrollController _mobileSongListController(WidgetTester tester) {
  final list = find.descendant(
    of: find.byType(MobileLayout),
    matching: find.byType(ListView),
  );
  return tester.widget<ListView>(list).controller!;
}

void main() {
  final api = _ScrollTestApi();

  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);

  setUp(() {
    api.reset();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'desktop restores All Songs and active playlist scroll position across restarts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const pl1 = Playlist(id: 'pl-1', name: '歌单一', createdAt: '');
      api.dbPlaylists.add(pl1);
      api.dbSongs.addAll(
        List.generate(120, (i) => _song(i.toString().padLeft(3, '0'))),
      );
      api.dbPlaylistSongs[pl1.id] = [
        for (var i = 0; i < 80; i++) i.toString().padLeft(3, '0'),
      ];

      // Session 1: scroll All Songs, then select pl-1 and scroll to a different offset.
      final session1 = await _mountMainLayout(tester);
      final listFinder = find.descendant(
        of: find.byType(SongTable),
        matching: find.byType(ListView),
      );
      await tester.drag(listFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.drag(listFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      final allSongsSavedOffset = _desktopSongListController(tester).offset;
      expect(allSongsSavedOffset, greaterThan(900));
      expect(find.text('Song 000'), findsNothing);

      // Switch to 歌单一: starts at top until scrolled.
      await session1.library.setActivePlaylist(pl1.id);
      await tester.pumpAndSettle();
      expect(_desktopSongListController(tester).offset, closeTo(0, 1));

      await tester.drag(listFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      final pl1SavedOffset = _desktopSongListController(tester).offset;
      expect(pl1SavedOffset, greaterThan(400));

      // Switching back to All Songs in-session keeps All Songs' offset.
      await session1.library.setActivePlaylist(null);
      await tester.pumpAndSettle();
      expect(
        _desktopSongListController(tester).offset,
        closeTo(allSongsSavedOffset, 1),
      );

      // Return to pl-1 before closing the app.
      await session1.library.setActivePlaylist(pl1.id);
      await tester.pumpAndSettle();
      expect(
        _desktopSongListController(tester).offset,
        closeTo(pl1SavedOffset, 1),
      );

      await _unmountSession(tester, session1);

      // Session 2: reopening restores BOTH 歌单一 and its exact scroll position.
      final session2 = await _mountMainLayout(tester);
      expect(session2.library.activePlaylistId, pl1.id);
      expect(
        _desktopSongListController(tester).offset,
        closeTo(pl1SavedOffset, 1),
      );
      expect(find.text('Song 000'), findsNothing);

      // Search filtering resets to top of matches without wiping pl-1's offset,
      // and clearing the filter restores pl-1's position without collapsing tags.
      session2.library.setSearchQuery('Song 001');
      await tester.pumpAndSettle();
      expect(_desktopSongListController(tester).offset, closeTo(0, 1));
      expect(find.text('Song 001'), findsOneWidget);

      session2.library.setSearchQuery('');
      await tester.pumpAndSettle();
      expect(
        _desktopSongListController(tester).offset,
        closeTo(pl1SavedOffset, 1),
      );
      final tagPoolAlign = tester.widget<Align>(
        find.descendant(
          of: find.byType(TagFilter),
          matching: find.byType(Align),
        ),
      );
      expect(tagPoolAlign.heightFactor, 1.0);

      await _unmountSession(tester, session2);
    },
  );

  testWidgets('desktop clamps saved scroll offset when list shrinks on reopen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    api.dbSongs.addAll(
      List.generate(120, (i) => _song(i.toString().padLeft(3, '0'))),
    );

    final session1 = await _mountMainLayout(tester);
    final controller1 = _desktopSongListController(tester);
    controller1.jumpTo(controller1.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(controller1.offset, greaterThan(4000));
    await _unmountSession(tester, session1);

    // Shrink the library before reopening so the saved offset exceeds max extent.
    api.dbSongs.removeRange(25, api.dbSongs.length);

    final session2 = await _mountMainLayout(tester);
    final controller2 = _desktopSongListController(tester);
    expect(controller2.offset, closeTo(controller2.position.maxScrollExtent, 1));
    expect(controller2.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await _unmountSession(tester, session2);
  });

  testWidgets('immediate app hide flushes mouse-wheel scroll position before exit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    api.dbSongs.addAll(
      List.generate(100, (i) => _song(i.toString().padLeft(3, '0'))),
    );

    final session1 = await _mountMainLayout(tester);
    final center = tester.getCenter(find.byType(SongTable));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final scrolledOffset = _desktopSongListController(tester).offset;
    expect(scrolledOffset, greaterThan(100));

    // Close/hide the window before the 200ms wheel settle/debounce completes.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await _unmountSession(tester, session1);

    final session2 = await _mountMainLayout(tester);
    expect(
      _desktopSongListController(tester).offset,
      closeTo(scrolledOffset, 1),
    );
    await _unmountSession(tester, session2);
  });

  testWidgets('mobile restores song list scroll position across restarts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const tag = [Tag(id: 1, name: 'Tagged')];
    api.dbSongs.addAll(
      List.generate(
        80,
        (i) => _song(
          i.toString().padLeft(3, '0'),
          tags: i.isEven ? tag : const [],
        ),
      ),
    );

    final session1 = await _mountMainLayout(tester);
    expect(find.byType(MobileLayout), findsOneWidget);
    final listFinder = find.descendant(
      of: find.byType(MobileLayout),
      matching: find.byType(ListView),
    );
    await tester.drag(listFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.drag(listFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    final savedOffset = _mobileSongListController(tester).offset;
    expect(savedOffset, greaterThan(600));
    expect(find.text('Song 000'), findsNothing);

    await _unmountSession(tester, session1);

    final session2 = await _mountMainLayout(tester);
    expect(_mobileSongListController(tester).offset, closeTo(savedOffset, 1));
    expect(find.text('Song 000'), findsNothing);
    await _unmountSession(tester, session2);
  });
}
