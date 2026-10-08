import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/widgets.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/ui_test_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'marquee motion must not rebuild song cells or read the library',
    (tester) async {
      final library = TestLibrary()
        ..songs = List.generate(5000, (i) => testSong('$i'));
      final audio = TestAudio();
      final theme = UIThemeProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
            ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ],
          child: MaterialApp(
            theme: theme.themeData,
            home: const Scaffold(body: SongTable()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = tester.getRect(find.text('Track 0'));
      final gesture = await tester.startGesture(
        row.center,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(15, 0));
      await tester.pump();
      final cells = library.lyricFlagReads;
      final reads = library.displayReads;
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(microseconds: 6061));
      }
      expect(
        library.displayReads - reads,
        0,
        reason: 'Pointer motion is a repaint, not a table rebuild',
      );
      expect(
        library.lyricFlagReads - cells,
        0,
        reason: 'Unchanged rows must retain their cells',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(audio.isDetailOpen, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      audio.dispose();
      library.dispose();
      theme.dispose();
    },
  );

  testWidgets('marquee paints the latest pointer position on the next frame', (
    tester,
  ) async {
    final library = TestLibrary()
      ..songs = List.generate(30, (i) => testSong('$i'));
    final audio = TestAudio();
    final theme = UIThemeProvider();
    final key = GlobalKey();
    await mountTable(
      tester,
      library,
      audio,
      theme,
      wrap: (table) => RepaintBoundary(key: key, child: table),
    );
    final start = tester.getCenter(find.text('Track 0'));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(start + const Offset(20, 16));
    await tester.pump();
    Future<int> sample(Offset point) async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return bytes.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          );
        } finally {
          image.dispose();
        }
      }))!;
    }

    final point = start + const Offset(30, 10);
    final before = await sample(point);
    await gesture.moveTo(start + const Offset(40, 16));
    await tester.pump(const Duration(microseconds: 6061));
    expect(
      await sample(point),
      isNot(before),
      reason: 'The rectangle must paint every pointer update',
    );
    await gesture.up();
    await tester.pump();
    expect(
      await sample(point),
      before,
      reason: 'Pointer release must remove the rectangle',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    theme.dispose();
  });

  testWidgets(
    'nested play does not open details or swallow the next row click',
    (tester) async {
      final library = TestLibrary()
        ..songs = List.generate(30, (i) => testSong('$i'));
      final audio = TestAudio();
      final theme = UIThemeProvider();
      await mountTable(tester, library, audio, theme);
      final cells = library.lyricFlagReads;
      await tester.tap(find.byTooltip('播放').first);
      await tester.pump();
      expect(audio.playCalls, 1);
      expect(audio.isDetailOpen, isFalse);
      // No old 320ms ignore window after pressing a row's play button.
      await tester.tap(find.text('Track 1'));
      await tester.pump();
      expect(audio.activeSong?.id, '1');
      expect(audio.isDetailOpen, isTrue);
      expect(
        library.lyricFlagReads - cells,
        lessThanOrEqualTo(18),
        reason:
            'Playback and active row changes must not rebuild the whole list',
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      audio.dispose();
      library.dispose();
      theme.dispose();
    },
  );

  testWidgets(
    'ctrl selection, reverse marquee, cancellation and scrolling retain selection behavior',
    (tester) async {
      final library = TestLibrary()
        ..songs = List.generate(100, (i) => testSong('$i'));
      final audio = TestAudio();
      final theme = UIThemeProvider();
      await mountTable(tester, library, audio, theme);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Track 1'));
      await tester.pump();
      expect(audio.isDetailOpen, isFalse);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Track 3')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        tester.getCenter(find.text('Track 2')) - const Offset(15, 0),
      );
      await tester.pump();
      await gesture.cancel();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track 2'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制所选歌曲'));
      await tester.pumpAndSettle();
      expect(library.clipboard!['songIds'], unorderedEquals(['1', '2', '3']));
      final reads = library.displayReads;
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(library.displayReads, reads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      audio.dispose();
      library.dispose();
      theme.dispose();
    },
  );

  testWidgets('a quick click still displays press feedback on the next frame', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Scaffold(
          body: Center(
            child: AetherButton(label: 'Click', onPressed: () => taps++),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Click')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
      reason: 'Down/up between frames must not erase click feedback',
    );
    await tester.pumpAndSettle();
  });
}

Future<void> mountTable(
  WidgetTester tester,
  TestLibrary library,
  TestAudio audio,
  UIThemeProvider theme, {
  Widget Function(Widget)? wrap,
}) async {
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
          body: wrap?.call(const SongTable()) ?? const SongTable(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
