import 'dart:ui' show PointerDeviceKind;
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/ui_test_fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('desktop pointer, drawer and button latency', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = TestLibrary()
      ..songs = List.generate(5000, (i) => testSong('$i'));
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
    final readsBefore = library.displayReads;
    final cellsBefore = library.lyricFlagReads;
    await binding.watchPerformance(() async {
      final row = tester.getRect(find.text('Track 0').first);
      final gesture = await tester.startGesture(
        row.center,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 120; i++) {
        await gesture.moveTo(
          row.center + Offset(15 + i * 2.0, 100 + (i % 40) * 2.0),
        );
        await tester.pump(const Duration(microseconds: 6061));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }, reportKey: 'desktop_marquee');
    binding.reportData!['marquee_work'] = {
      'library_reads': library.displayReads - readsBefore,
      'cell_checks': library.lyricFlagReads - cellsBefore,
    };
    final timestamps = <int>[];
    var recording = true;
    void record(Duration time) {
      if (!recording) return;
      timestamps.add(time.inMicroseconds);
    }

    SchedulerBinding.instance.addPersistentFrameCallback(record);
    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Track 1').first);
        await tester.pumpAndSettle();
        expect(audio.isDetailOpen, isTrue);
        await tester.tap(find.byTooltip('关闭详情'));
        await tester.pumpAndSettle();
        expect(audio.isDetailOpen, isFalse);
      }
    }, reportKey: 'desktop_drawer');
    recording = false;
    final intervals = <int>[];
    for (var i = 1; i < timestamps.length; i++) {
      final delta = timestamps[i] - timestamps[i - 1];
      if (delta > 0 && delta < 50000) intervals.add(delta);
    }
    intervals.sort();
    binding.reportData!['frame_cadence_us'] = {
      'samples': intervals.length,
      'median': intervals.isEmpty ? null : intervals[intervals.length ~/ 2],
      'reported_display_hz': tester.view.display.refreshRate,
    };
    if (const bool.fromEnvironment('AETHERIA_EXPECT_MONITOR_VSYNC')) {
      expect(intervals.length, greaterThan(100));
      expect(
        intervals[intervals.length ~/ 2],
        lessThanOrEqualTo(1e6 / tester.view.display.refreshRate * 1.25),
        reason: 'Actual animation timestamps must follow the monitor clock',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    theme.dispose();
    sync.dispose();
  });
}
