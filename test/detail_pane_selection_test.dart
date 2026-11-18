import 'dart:ui' show PointerDeviceKind;

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_panel_widgets.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/ui_test_fakes.dart';

class _PhigrosTestAudio extends TestAudio {
  @override
  ({bool enabled, double volume, int offsetMs, String? chartPath})
  resolveHitsoundForSong(Song? song) {
    return (enabled: true, volume: 0.75, offsetMs: 0, chartPath: null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboardText = args['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildPaneHost({
    required AudioPlayerProvider audio,
    required LibraryProvider library,
    required UIThemeProvider theme,
    double width = 400,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
        theme: theme.themeData,
        home: Scaffold(
          body: SizedBox(width: width, height: 720, child: const DetailPane()),
        ),
      ),
    );
  }

  Future<void> mouseDragSelect(WidgetTester tester, Rect rect) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset(rect.left - 4, rect.center.dy));
    await tester.pump();
    await gesture.down(Offset(rect.left - 4, rect.center.dy));
    await tester.pump();
    await gesture.moveTo(Offset(rect.right + 4, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await gesture.removePointer();
  }

  testWidgets('DetailPane header supports mouse drag copy while preserving tap-to-edit', (
    tester,
  ) async {
    const song = Song(
      id: 'song-1',
      title: '我们的爱',
      artist: 'F.I.R.飞儿乐团',
      rating: 0,
      createdAt: '',
      versions: [
        AudioVersion(
          id: 'ver-1',
          songId: 'song-1',
          filepath: 'a.flac',
          originalName: '我们的爱 - 黄霄雲.flac',
          format: 'FLAC',
          duration: 289,
          fileSize: 65326284,
          isEnabled: true,
          isPrimary: true,
          metadataScanned: true,
        ),
      ],
      tags: [],
    );

    final library = TestLibrary()..songs = [song];
    final audio = TestAudio()
      ..activeSong = song
      ..activeTab = 'versions';
    final theme = UIThemeProvider();
    addTearDown(() {
      library.dispose();
      audio.dispose();
      theme.dispose();
    });

    await tester.pumpWidget(
      buildPaneHost(audio: audio, library: library, theme: theme),
    );
    await tester.pumpAndSettle();

    final artistFinder = find.text('F.I.R.飞儿乐团');
    expect(artistFinder, findsOneWidget);

    await mouseDragSelect(tester, tester.getRect(artistFinder));

    // Drag-selecting must not open inline edit mode.
    expect(find.byType(EditableText), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(clipboardText, 'F.I.R.飞儿乐团');

    // A plain tap still enters inline edit mode.
    await tester.tap(artistFinder);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('SongVersionList allows copying version artist names and keeps controls disabled from selection', (
    tester,
  ) async {
    const song = Song(
      id: 'song-1',
      title: '我们的爱',
      artist: 'F.I.R.飞儿乐团',
      rating: 0,
      createdAt: '',
      versions: [
        AudioVersion(
          id: 'ver-1',
          songId: 'song-1',
          filepath: 'a.aac',
          originalName: '我们的爱 - F.I.R.飞儿乐团.aac',
          format: 'AAC',
          bitrate: 213000,
          sampleRate: 48000,
          duration: 290,
          fileSize: 7969177,
          loudness: -10.8,
          isEnabled: true,
          isPrimary: false,
          metadataScanned: true,
        ),
        AudioVersion(
          id: 'ver-2',
          songId: 'song-1',
          filepath: 'b.flac',
          originalName: '我们的爱 - 黄霄雲.flac',
          format: 'FLAC',
          bitrate: 1808000,
          sampleRate: 48000,
          duration: 289,
          fileSize: 65326284,
          loudness: -7.2,
          isEnabled: true,
          isPrimary: true,
          metadataScanned: true,
        ),
      ],
      tags: [],
    );

    final library = TestLibrary()..songs = [song];
    final audio = TestAudio()
      ..activeSong = song
      ..activeTab = 'versions';
    final theme = UIThemeProvider();
    addTearDown(() {
      library.dispose();
      audio.dispose();
      theme.dispose();
    });

    await tester.pumpWidget(
      buildPaneHost(audio: audio, library: library, theme: theme),
    );
    await tester.pumpAndSettle();

    final versionTitleFinder = find.text('我们的爱 - 黄霄雲.flac');
    expect(versionTitleFinder, findsOneWidget);

    await mouseDragSelect(tester, tester.getRect(versionTitleFinder));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(clipboardText, '我们的爱 - 黄霄雲.flac');

    // Interactive action controls stay outside selection containers.
    final primaryToggleContainer = find.ancestor(
      of: find.text('设为默认播放版本'),
      matching: find.byType(SelectionContainer),
    );
    expect(
      tester.widget<SelectionContainer>(primaryToggleContainer.first).registrar,
      isNull,
    );
  });

  testWidgets('PhigrosDetailPanel allows copying composer and charter names', (
    tester,
  ) async {
    const phiSong = Song(
      id: 'phi-1',
      title: 'Rrhar\'il',
      artist: 'Team Grimoire',
      rating: 0,
      createdAt: '',
      versions: [
        AudioVersion(
          id: 'phi-v1',
          songId: 'phi-1',
          filepath: 'phi.flac',
          originalName: 'Rrhar\'il.flac',
          format: 'FLAC',
          duration: 150,
          fileSize: 10000,
          isEnabled: true,
          isPrimary: true,
          metadataScanned: true,
        ),
      ],
      tags: [],
      phigros: PhigrosSongMeta(
        phigrosId: 'Rrharil.TeamGrimoire.0',
        chapter: '第七章 · 时钟链接',
        composer: 'Team Grimoire',
        illustrator: 'SELEN',
        selectedDifficulty: 'AT',
        hitsoundMode: 'global',
        charts: [
          PhigrosChartMeta(
            difficulty: 'AT',
            sortRank: 3,
            rating: 16.5,
            charter: 'Barbarianerman',
            bpmMin: 180,
            bpmMax: 180,
            chartOffsetMs: 0,
            noteCount: 1000,
            tapCount: 500,
            dragCount: 200,
            holdCount: 200,
            flickCount: 100,
            chartRelPath: 'c.json',
          ),
        ],
      ),
    );

    final library = TestLibrary()..songs = [phiSong];
    final audio = _PhigrosTestAudio()
      ..activeSong = phiSong
      ..activeTab = 'phigros';
    final theme = UIThemeProvider();
    addTearDown(() {
      library.dispose();
      audio.dispose();
      theme.dispose();
    });

    await tester.pumpWidget(
      buildPaneHost(audio: audio, library: library, theme: theme, width: 420),
    );
    await tester.pumpAndSettle();

    final composerFinder = find.text('Team Grimoire').last;
    await mouseDragSelect(tester, tester.getRect(composerFinder));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(clipboardText, 'Team Grimoire');

    final chipContainer = find.ancestor(
      of: find.text('Lv.16.5'),
      matching: find.byType(SelectionContainer),
    );
    expect(
      tester.widget<SelectionContainer>(chipContainer.first).registrar,
      isNull,
    );
  });

  testWidgets('LyricPanelHeader allows copying version name and excludes empty artist placeholder', (
    tester,
  ) async {
    const version = AudioVersion(
      id: 'ver-1',
      songId: 'song-1',
      filepath: 'a.flac',
      originalName: '我们的爱 - 黄霄雲.flac',
      format: 'FLAC',
      duration: 289,
      fileSize: 65326284,
      isEnabled: true,
      isPrimary: true,
      metadataScanned: true,
    );
    const song = Song(
      id: 'song-1',
      title: '我们的爱',
      artist: null,
      rating: 0,
      createdAt: '',
      versions: [version],
      tags: [],
    );

    final library = TestLibrary()..songs = [song];
    final audio = TestAudio()..activeSong = song;
    final theme = UIThemeProvider();
    addTearDown(() {
      library.dispose();
      audio.dispose();
      theme.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: const Scaffold(
            body: Column(
              children: [
                Expanded(child: SizedBox(width: 400, child: DetailPane())),
                SizedBox(
                  width: 400,
                  child: LyricPanelHeader(
                    audioVersion: version,
                    savedLyric: null,
                    actions: [],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final placeholderContainer = find.ancestor(
      of: find.text('未知歌手'),
      matching: find.byType(SelectionContainer),
    );
    expect(
      tester.widget<SelectionContainer>(placeholderContainer.first).registrar,
      isNull,
    );

    final headerVersionFinder = find.descendant(
      of: find.byType(LyricPanelHeader),
      matching: find.text('我们的爱 - 黄霄雲.flac'),
    );
    await mouseDragSelect(tester, tester.getRect(headerVersionFinder));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(clipboardText, '我们的爱 - 黄霄雲.flac');
  });
}
