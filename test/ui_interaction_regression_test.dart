import 'dart:ui' as ui;

import 'support/ui_test_fakes.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/widgets.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';
import 'package:aetheria/features/player/ui/play_bar.dart';
import 'package:aetheria/features/player/ui/playback_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'press feedback starts before tap recognition and cancels on scroll',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          ListView(
            children: [
              AetherPressable(
                onTap: () => taps++,
                child: const SizedBox(height: 90, child: Text('Press')),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Press')),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1),
      );
      expect(taps, 0);
      await gesture.moveBy(const Offset(0, -150));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    },
  );

  testWidgets('desktop scrub previews immediately and commits exactly once', (
    tester,
  ) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            width: 400,
            child: AetherSeekBar(progress: 0, onSeek: seeks.add),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(AetherSeekBar));
    final gesture = await tester.startGesture(
      Offset(rect.left + 10, rect.center.dy),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      greaterThan(0.4),
    );
    final fill = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(ColoredBox),
    );
    expect(tester.getSize(fill).height, 4);
    expect(tester.getSize(fill).width, greaterThan(160));
    final thumb = find.byKey(const ValueKey('aether-seek-thumb'));
    expect(
      tester.getCenter(thumb).dx,
      closeTo(rect.left + tester.getSize(fill).width, 0.01),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(0.525, 0.02));
  });

  for (final config in [
    AppThemeConfig.dark,
    AppThemeConfig.light,
    AppThemeConfig.pink,
  ]) {
    testWidgets('seek bar paints progress and thumb in ${config.accent}', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      for (final progress in [0.0, 0.25, 0.5, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAetheriaThemeData(config),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: 400,
                    child: AetherSeekBar(progress: progress, onSeek: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final barRect = tester.getRect(find.byType(AetherSeekBar));
        final thumbRect = tester.getRect(
          find.byKey(const ValueKey('aether-seek-thumb')),
        );
        expect(thumbRect.size, const Size(10, 10));
        expect(thumbRect.left, greaterThanOrEqualTo(barRect.left));
        expect(thumbRect.right, lessThanOrEqualTo(barRect.right));
        expect(
          thumbRect.center.dx - barRect.left,
          closeTo((400 * progress).clamp(5.0, 395.0), 0.01),
        );
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        });
        final thumbLeft = thumbRect.left - barRect.left;
        final thumbRight = thumbRect.right - barRect.left;
        bool isActivePixel(int x, int y) {
          final offset = (y * 400 + x) * 4;
          final rgba = pixels!.sublist(offset, offset + 4);
          return rgba[0] == (config.accent.r * 255).round() &&
              rgba[1] == (config.accent.g * 255).round() &&
              rgba[2] == (config.accent.b * 255).round() &&
              rgba[3] == 255;
        }

        for (var x = 0; x < 400; x++) {
          // Exclude the circle where it extends past the played track.
          if (x >= thumbLeft - 1 && x <= thumbRight + 1) continue;
          expect(
            isActivePixel(x, 8),
            x < 400 * progress,
            reason: 'Visible track at x=$x must match progress $progress',
          );
        }
        expect(
          isActivePixel((thumbRect.center.dx - barRect.left).floor(), 4),
          isTrue,
          reason: 'The thumb must be visible above the thin track',
        );
      }
    });
  }

  testWidgets('playback clock leaves transport untouched and updates time', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final audio = TestAudio();
    final library = TestLibrary();
    final theme = UIThemeProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: _app(const PlayBar()),
      ),
    );
    await tester.pumpAndSettle();
    final buttonFinder = find.widgetWithIcon(
      AetherIconButton,
      Icons.skip_next_rounded,
    );
    final transportBefore = tester.widget(buttonFinder);
    audio.positionListenable.value = const Duration(seconds: 35);
    await tester.pump();
    expect(find.text('00:35 / 02:00'), findsOneWidget);
    expect(identical(transportBefore, tester.widget(buttonFinder)), isTrue);
    final fill = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(ColoredBox),
    );
    final rect = tester.getRect(find.byType(AetherSeekBar));
    expect(tester.getSize(fill).height, 4);
    expect(tester.getSize(fill).width, closeTo(rect.width * 35 / 120, 0.01));
    final thumb = find.byKey(const ValueKey('aether-seek-thumb'));
    expect(
      tester.getCenter(thumb).dx,
      closeTo(rect.left + rect.width * 35 / 120, 0.01),
    );
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();
    expect(audio.seeks, [const Duration(seconds: 90)]);
    expect(tester.getSize(fill).width, closeTo(rect.width * 0.75, 0.01));
    expect(
      tester.getCenter(thumb).dx,
      closeTo(rect.left + rect.width * 0.75, 0.01),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    theme.dispose();
  });

  testWidgets('desktop detail drawer removes its barrier after every close', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final audio = TestAudio();
    final library = TestLibrary();
    final theme = UIThemeProvider();
    final sync = TestSync();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
        ],
        child: MaterialApp(theme: theme.themeData, home: const MainLayout()),
      ),
    );
    await tester.pumpAndSettle();
    final drawerBarrier = find.descendant(
      of: find.byType(MainLayout),
      matching: find.byType(ModalBarrier),
    );
    for (var i = 0; i < 3; i++) {
      audio.setDetailOpen(true);
      await tester.pumpAndSettle();
      expect(find.byType(DetailPane), findsOneWidget);
      expect(drawerBarrier, findsOneWidget);
      await tester.tapAt(const Offset(450, 250));
      await tester.pumpAndSettle();
      expect(audio.isDetailOpen, isFalse);
      expect(find.byType(DetailPane), findsNothing);
      expect(drawerBarrier, findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    theme.dispose();
    sync.dispose();
  });

  testWidgets('mobile scrub avoids engine calls until release', (tester) async {
    final audio = TestAudio();
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            width: 360,
            child: PlaybackProgress(audio: audio, showTime: true),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(rect.left + 30, rect.center.dy),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    audio.positionListenable.value = const Duration(seconds: 1);
    await tester.pump();
    expect(audio.seeks, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0.25));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(audio.seeks, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
  });

  testWidgets(
    'tall popup remains scrollable and dismisses without click-through',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      int? selected;
      var backgroundTaps = 0;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps++,
              child: Center(
                child: AetherButton(
                  label: 'Open',
                  onPressed: () async {
                    selected = await showAetherMenu<int>(
                      context: context,
                      globalPosition: const Offset(290, 230),
                      items: List.generate(
                        30,
                        (i) => AetherMenuItem(value: i, label: 'Action $i'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action 29'));
      await tester.pumpAndSettle();
      expect(selected, 29);
      expect(backgroundTaps, 0);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Action 0'), findsNothing);
      expect(backgroundTaps, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replacing a dismissing toast leaves the new toast intact', (
    tester,
  ) async {
    late BuildContext overlayContext;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            overlayContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    showAetherToast(
      overlayContext,
      message: 'First',
      duration: const Duration(milliseconds: 250),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    showAetherToast(overlayContext, message: 'Second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact sheet only occupies its content and barrier dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: AetherButton(
              label: 'Sheet',
              onPressed: () => showAetherSheet<void>(
                context: context,
                builder: (_) => const SizedBox(
                  height: 100,
                  child: Center(child: Text('Content')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(160));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile drawer blocks the mini player and scroll avoids refiltering',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final audio = TestAudio()..playingSong = testSong('0');
      final library = TestLibrary()
        ..songs = List.generate(100, (i) => testSong('$i'));
      final theme = UIThemeProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ],
          child: MaterialApp(
            theme: theme.themeData,
            home: const MobileLayout(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reads = library.displayReads;
      await tester.drag(find.byType(ListView).first, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(library.displayReads, reads);
      final nextPosition = tester.getCenter(find.byTooltip('下一首'));
      await tester.tap(find.byTooltip('歌单'));
      await tester.pumpAndSettle();
      await tester.tapAt(nextPosition);
      await tester.pumpAndSettle();
      expect(audio.nextCalls, 0);
      await tester.tapAt(const Offset(319, 700));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      audio.dispose();
      library.dispose();
      theme.dispose();
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: buildAetheriaThemeData(AppThemeConfig.dark),
  home: Scaffold(body: child),
);
