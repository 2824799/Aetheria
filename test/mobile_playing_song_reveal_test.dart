import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/mobile/mobile_mini_player.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';
import 'package:aetheria/features/player/ui/song_cover_art.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestLibraryProvider extends LibraryProvider {
  @override
  Future<String?> ensureSongCover(Song song) async => null;
}

Song _song() {
  return const Song(
    id: 'playing-song',
    title: '正在播放',
    artist: '测试歌手',
    rating: 0,
    createdAt: '',
    versions: [],
    tags: [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('mobile scroll estimate uses mounted variable-height samples', () {
    final offset = estimateMobileSongScrollOffset(
      targetIndex: 10,
      itemCount: 20,
      samples: const <MobileSongScrollSample>[
        (index: 4, centeredOffset: 300, extent: 70),
        (index: 6, centeredOffset: 450, extent: 80),
      ],
      minScrollExtent: 0,
      maxScrollExtent: 1200,
    );

    expect(offset, 750);
  });

  test('mobile scroll estimate falls back to list progress and clamps', () {
    expect(
      estimateMobileSongScrollOffset(
        targetIndex: 5,
        itemCount: 11,
        samples: const <MobileSongScrollSample>[],
        minScrollExtent: 0,
        maxScrollExtent: 1000,
      ),
      500,
    );
    expect(
      estimateMobileSongScrollOffset(
        targetIndex: 100,
        itemCount: 11,
        samples: const <MobileSongScrollSample>[],
        minScrollExtent: 0,
        maxScrollExtent: 1000,
      ),
      1000,
    );
  });

  testWidgets('mobile cover supports tap and long-press independently', (
    tester,
  ) async {
    final themeProvider = UIThemeProvider();
    final libraryProvider = _TestLibraryProvider();
    final audioProvider = AudioPlayerProvider();
    var openDetailCount = 0;
    var revealCount = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
        ],
        child: MaterialApp(
          theme: themeProvider.themeData,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: MobileMiniPlayer(
                  playingSong: _song(),
                  cfg: themeProvider.currentTheme,
                  audioProvider: audioProvider,
                  onOpenDetail: () => openDetailCount++,
                  onPlayingSongLongPress: () => revealCount++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final cover = find.byType(SongCoverArt);
    expect(cover, findsOneWidget);

    await tester.tap(cover);
    await tester.pump();
    expect(openDetailCount, 1);
    expect(revealCount, 0);

    await tester.longPress(cover);
    await tester.pump();
    expect(openDetailCount, 1);
    expect(revealCount, 1);

    await tester.longPress(find.text('正在播放'));
    await tester.pump();
    expect(openDetailCount, 1);
    expect(revealCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    libraryProvider.dispose();
  });
}
