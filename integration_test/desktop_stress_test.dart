// Probe the production painter so thumb gestures respect its actual hit area.
// ignore_for_file: invalid_use_of_protected_member, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui'
    show FramePhase, FrameTiming, PointerDeviceKind, PlatformDispatcher;

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/ui_test_fakes.dart';

// Optional path must point to a disposable COPY of a library, never the user's
// database. Real metadata/covers make rapid thumb scrubbing representative.
const _libraryPath = String.fromEnvironment('AETHERIA_BENCH_LIBRARY');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // GTK may enable native accessibility after the test has already recorded
  // its initial handle count on a separate UI thread. Start with semantics
  // enabled so that startup notification cannot look like a leaked test handle.
  binding.platformDispatcher.semanticsEnabledTestValue = true;
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  testWidgets('600 songs: thumb, wheel, drawer and interrupted drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'aetheria-theme': 'pink'});
    final library = TestLibrary();
    if (_libraryPath.isNotEmpty) {
      await tester.runAsync(() async {
        await RustLib.init();
        await music.initializeLibraryPath(path: _libraryPath);
        library.songs = (await music.getSongs()).take(600).toList();
        library.tags = await music.getTags();
        library.libraryPath = _libraryPath;
        library.songIdsWithLyrics = {
          for (final song in library.songs)
            if ((await music.getLyricsForSong(songId: song.id)).isNotEmpty)
              song.id,
        };
        final originals = List<Song>.of(library.songs);
        while (library.songs.length < 600 && originals.isNotEmpty) {
          final song = originals[library.songs.length % originals.length];
          library.songs.add(
            Song(
              id: 'snapshot-copy-${library.songs.length}',
              title: '${song.title} (${library.songs.length})',
              artist: song.artist,
              lyrics: song.lyrics,
              coverPath: song.coverPath,
              rating: song.rating,
              createdAt: song.createdAt,
              versions: song.versions,
              tags: song.tags,
            ),
          );
        }
      });
    } else {
      library.songs = List.generate(
        600,
        (i) => Song(
          id: '$i',
          title: '歌曲 $i · いったりきたりの花魁道中',
          artist: '歌手 Artist ${i % 25}',
          rating: 0,
          createdAt: '',
          lyrics: '[00:00.00]歌词预览 $i\n[00:05.00]下一行歌词',
          versions: const [],
          tags: const [Tag(id: 1, name: '日语', color: '#EA8BA4')],
        ),
      );
    }
    expect(library.songs.length, 600);
    final audio = TestAudio()..playingSong = library.songs.first;
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
    final table = find.byType(SongTable);
    final list = find.descendant(of: table, matching: find.byType(ListView));
    final listController = tester.widget<ListView>(list).controller!;
    final position = listController.position;
    final horizontal = tester
        .state<ScrollableState>(
          find.descendant(of: table, matching: find.byType(Scrollable)).first,
        )
        .position;
    horizontal.jumpTo(horizontal.maxScrollExtent);
    await tester.pumpAndSettle();
    final scrollbar = find
        .descendant(
          of: table,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RawScrollbar && widget.controller == listController,
          ),
        )
        .last;
    final scrollbarState = tester.state<RawScrollbarState>(scrollbar);
    final textCache = tester
        .widget<SongTableText>(find.byType(SongTableText).first)
        .cache;
    final timings = <FrameTiming>[];
    void recordTimings(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(recordTimings);
    final windows = <String, (int, int)>{};
    final work = <String, Object?>{};
    final interactions = <Map<String, Object>>[];
    final animationWindows = <Map<String, Object>>[];
    final thumbPasses = <Map<String, Object>>[];
    final thumbInputs = <List<num>>[];
    final thumbFrames = <List<num>>[];
    var latestThumbInput = -1;
    var recordingFrames = true;
    Animation<Offset>? drawerAnimation;
    int? animationStart;
    AnimationStatus? animationDirection;
    var currentPhase = '';
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!recordingFrames || !currentPhase.startsWith('thumb')) return;
      thumbFrames.add([
        tester.binding.platformDispatcher.frameData.frameNumber,
        latestThumbInput,
        developer.Timeline.now,
        position.pixels,
      ]);
    });
    Future<void> moveThumb(TestGesture gesture, Offset point) async {
      final seq = thumbInputs.length;
      latestThumbInput = seq;
      final sent = developer.Timeline.now;
      await gesture.moveTo(point);
      thumbInputs.add([seq, sent, developer.Timeline.now, position.pixels]);
    }

    void recordAnimation(AnimationStatus status) {
      final now = developer.Timeline.now;
      if (animationStart != null) {
        animationWindows.add({
          'phase': currentPhase,
          'direction': animationDirection!.name,
          'start_us': animationStart!,
          'end_us': now,
          'interrupted':
              status == AnimationStatus.forward ||
              status == AnimationStatus.reverse,
        });
      }
      animationStart =
          status == AnimationStatus.forward || status == AnimationStatus.reverse
          ? now
          : null;
      animationDirection = status;
    }

    var ticks = 0;
    final playback = Timer.periodic(const Duration(milliseconds: 250), (_) {
      audio.positionListenable.value = Duration(milliseconds: ++ticks * 250);
    });

    Future<void> pause(int milliseconds) =>
        Future<void>.delayed(Duration(milliseconds: milliseconds));
    Future<void> measure(String name, Future<void> Function() action) async {
      await tester.runAsync(() => pause(300));
      final reads = library.displayReads;
      final cells = library.lyricFlagReads;
      final textMisses = textCache.layoutMisses;
      final idleLayouts = textCache.idleLayouts;
      final start = developer.Timeline.now;
      currentPhase = name;
      await tester.runAsync(action);
      expect(tester.takeException(), isNull, reason: '$name must complete');
      final end = developer.Timeline.now;
      windows[name] = (start, end);
      work[name] = {
        'library_reads': library.displayReads - reads,
        'lyric_checks': library.lyricFlagReads - cells,
        'text_layout_misses': textCache.layoutMisses - textMisses,
        'idle_text_layouts': textCache.idleLayouts - idleLayouts,
        'cached_text_layouts': textCache.cachedLayouts,
        'pending_warmup_formats': textCache.pendingWarmupFormats,
      };
    }

    try {
      await tester.runAsync(() => pause(1500));
      // Expose the automatic scrollbar in the baseline before measuring its
      // gestures. Preparation/idle time must not lower the reported FPS.
      position.jumpTo(1);
      await tester.runAsync(() => pause(80));
      await measure('thumb_scrub', () async {
        final bounds = tester.getRect(scrollbar);
        final box = tester.renderObject<RenderBox>(scrollbar);
        final painter = scrollbarState.scrollbarPainter;
        final thumbX =
            box.size.width -
            painter.crossAxisMargin -
            (painter.padding.resolve(TextDirection.ltr).right) -
            painter.thickness / 2;
        final thumbY =
            List.generate(
              box.size.height.floor(),
              (i) => i.toDouble(),
            ).firstWhere(
              (y) =>
                  scrollbarState.scrollbarPainter.hitTestOnlyThumbInteractive(
                    Offset(thumbX, y),
                    PointerDeviceKind.mouse,
                  ),
            );
        final origin = box.localToGlobal(Offset(thumbX, thumbY + 8));
        final gesture = await tester.startGesture(
          origin,
          kind: PointerDeviceKind.mouse,
        );
        for (var pass = 0; pass < 6; pass++) {
          final passStart = developer.Timeline.now;
          for (var step = 1; step <= 120; step++) {
            final fraction = pass.isEven ? step / 120 : 1 - step / 120;
            await moveThumb(
              gesture,
              Offset(origin.dx, origin.dy + fraction * (bounds.height - 70)),
            );
            await pause(3);
          }
          if (pass.isEven) {
            expect(position.pixels, greaterThan(position.maxScrollExtent * .8));
          }
          thumbPasses.add({
            'pass': pass,
            'start_us': passStart,
            'end_us': developer.Timeline.now,
          });
        }
        await gesture.up();
        work['thumb_final_fraction'] =
            position.pixels / position.maxScrollExtent;
        expect(audio.isDetailOpen, isFalse);
      });
      position.jumpTo(1);
      await tester.runAsync(() => pause(100));
      await measure('thumb_step_latency', () async {
        final box = tester.renderObject<RenderBox>(scrollbar);
        final painter = scrollbarState.scrollbarPainter;
        final x =
            box.size.width -
            painter.crossAxisMargin -
            painter.padding.resolve(TextDirection.ltr).right -
            painter.thickness / 2;
        final y = List.generate(box.size.height.floor(), (i) => i.toDouble())
            .firstWhere(
              (y) => painter.hitTestOnlyThumbInteractive(
                Offset(x, y),
                PointerDeviceKind.mouse,
              ),
            );
        final origin = box.localToGlobal(Offset(x, y + 8));
        final gesture = await tester.startGesture(
          origin,
          kind: PointerDeviceKind.mouse,
        );
        for (final fraction in [.15, .8, .3, .9, .1, .7, .25, .85]) {
          await moveThumb(
            gesture,
            origin + Offset(0, fraction * (box.size.height - 70)),
          );
          await pause(140);
        }
        await gesture.up();
      });
      position.jumpTo(position.maxScrollExtent / 2);
      await measure('wheel_scroll', () async {
        final center = tester.getCenter(list);
        for (var i = 0; i < 480; i++) {
          tester.binding.handlePointerEventForSource(
            PointerScrollEvent(
              viewId: tester.view.viewId,
              position: center,
              scrollDelta: Offset(0, (i ~/ 80).isEven ? 36 : -36),
            ),
            source: TestBindingEventSource.test,
          );
          if (i == 79) {
            expect(
              position.pixels,
              greaterThan(position.maxScrollExtent / 2 + 1000),
            );
          }
          await pause(3);
        }
      });
      position.jumpTo(0);
      final firstTitle = library.displaySongs.first.title;
      final firstSong = find.descendant(
        of: table,
        matching: find.text(firstTitle),
      );
      Offset panelPosition() => tester.getTopLeft(find.byType(DetailPane));
      await measure('drawer_cycles', () async {
        for (var i = 0; i < 12; i++) {
          await tester.tap(firstSong.first);
          await pause(300);
          expect(audio.isDetailOpen, isTrue);
          if (drawerAnimation == null) {
            drawerAnimation = tester
                .widget<SlideTransition>(
                  find
                      .ancestor(
                        of: find.byType(DetailPane),
                        matching: find.byType(SlideTransition),
                      )
                      .first,
                )
                .position;
            drawerAnimation!.addStatusListener(recordAnimation);
          }
          final before = panelPosition();
          final pressedAt = developer.Timeline.now;
          await tester.tap(find.byTooltip('关闭详情'));
          await pause(24);
          interactions.add({
            'kind': 'close',
            'sample_after_us': developer.Timeline.now - pressedAt,
            'movement_px': panelPosition().dx - before.dx,
          });
          await pause(240);
          expect(audio.isDetailOpen, isFalse);
        }
      });
      await measure('drawer_interruptions', () async {
        for (var i = 0; i < 20; i++) {
          await tester.tap(firstSong.first);
          await pause(65);
          await tester.tapAt(
            tester.getRect(table).topLeft + const Offset(80, 80),
          );
          await pause(30);
          // A new request during the close must reverse from the current
          // visible position. This exercises the production state transition.
          audio.setDetailOpen(true);
          await pause(65);
          await tester.tapAt(
            tester.getRect(table).topLeft + const Offset(80, 80),
          );
          await pause(220);
          expect(audio.isDetailOpen, isFalse);
        }
      });
      await tester.runAsync(() => pause(1200));
      // The test wrapper can miss the initial display update on the separate
      // UI thread. Read the native view's current display for native runs.
      final hz = PlatformDispatcher.instance.views.first.display.refreshRate;
      final report = <String, Object?>{
        'songs': library.songs.length,
        'real_library_snapshot': _libraryPath.isNotEmpty,
        'display_hz': hz,
        'view_physical_size': [
          tester.view.physicalSize.width,
          tester.view.physicalSize.height,
        ],
        'device_pixel_ratio': tester.view.devicePixelRatio,
        'work': work,
        'close_response': interactions,
        'animation_windows': animationWindows,
        'thumb_passes': thumbPasses,
        'thumb_input_columns': [
          'sequence',
          'sent_us',
          'handled_us',
          'scroll_offset',
        ],
        'thumb_inputs': thumbInputs,
        'thumb_frame_columns': [
          'frame_number',
          'input_sequence',
          'sample_us',
          'scroll_offset',
        ],
        'thumb_frames': thumbFrames,
        'frame_timing_columns': [
          'frame_number',
          'vsync_start_us',
          'build_start_us',
          'build_finish_us',
          'raster_start_us',
          'raster_finish_us',
          'raster_finish_wall_us',
        ],
        'frame_timings': [
          for (final f in timings)
            [
              f.frameNumber,
              for (final phase in FramePhase.values)
                f.timestampInMicroseconds(phase),
            ],
        ],
        'phases': {
          for (final entry in windows.entries)
            entry.key: _summarize(timings, entry.value, hz),
        },
      };
      binding.reportData = {'desktop_stress': report};
      print('AETHERIA_STRESS ${jsonEncode(report)}');
      expect(timings.length, greaterThan(100));
      final error = tester.takeException();
      if (error != null) print('AETHERIA_STRESS_PENDING_ERROR $error');
      expect(error, isNull);
    } catch (error, stack) {
      print('AETHERIA_STRESS_FAILURE $error\n$stack');
      rethrow;
    } finally {
      recordingFrames = false;
      drawerAnimation?.removeStatusListener(recordAnimation);
      playback.cancel();
      SchedulerBinding.instance.removeTimingsCallback(recordTimings);
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        library.dispose();
        theme.dispose();
        sync.dispose();
      } catch (error, stack) {
        print('AETHERIA_STRESS_TEARDOWN_ERROR $error\n$stack');
        rethrow;
      }
    }
  });
}

Map<String, Object> _summarize(
  List<FrameTiming> all,
  (int, int) window,
  double hz,
) {
  final frames = all.where((f) {
    final time = f.timestampInMicroseconds(FramePhase.buildStart);
    return time >= window.$1 && time <= window.$2;
  }).toList();
  final build = frames.map((f) => f.buildDuration.inMicroseconds).toList()
    ..sort();
  final raster = frames.map((f) => f.rasterDuration.inMicroseconds).toList()
    ..sort();
  final total = frames.map((f) => f.totalSpan.inMicroseconds).toList()..sort();
  final vsync = frames.map((f) => f.vsyncOverhead.inMicroseconds).toList()
    ..sort();
  int percentile(List<int> values, double p) =>
      values.isEmpty ? 0 : values[((values.length - 1) * p).round()];
  return {
    'start_us': window.$1,
    'end_us': window.$2,
    'frames': frames.length,
    'build_p50_us': percentile(build, .5),
    'build_p95_us': percentile(build, .95),
    'build_p99_us': percentile(build, .99),
    'build_max_us': percentile(build, 1),
    'raster_p50_us': percentile(raster, .5),
    'raster_p95_us': percentile(raster, .95),
    'raster_p99_us': percentile(raster, .99),
    'raster_max_us': percentile(raster, 1),
    'total_span_p50_us': percentile(total, .5),
    'total_span_p95_us': percentile(total, .95),
    'total_span_max_us': percentile(total, 1),
    'vsync_overhead_p95_us': percentile(vsync, .95),
    'vsync_overhead_max_us': percentile(vsync, 1),
    'over_refresh_budget': frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 1e6 / hz ||
              f.rasterDuration.inMicroseconds > 1e6 / hz,
        )
        .length,
  };
}
