import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('continuous native rendering cadence', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 2),
    )..repeat();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            painter: _FramePainter(controller),
            size: Size.infinite,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    final times = <int>[];
    final timings = <FrameTiming>[];
    final clock = Stopwatch()..start();
    var recording = true;
    void record(Duration _) {
      if (recording) times.add(clock.elapsedMicroseconds);
    }

    void recordTimings(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addPersistentFrameCallback(record);
    SchedulerBinding.instance.addTimingsCallback(recordTimings);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 10)),
    );
    recording = false;
    SchedulerBinding.instance.removeTimingsCallback(recordTimings);
    final intervals = <int>[
      for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
    ]..sort();
    final report = <String, Object>{
      'display_hz': tester.view.display.refreshRate,
      'frames': times.length,
      'wall_fps': times.length < 2
          ? 0
          : (times.length - 1) * 1e6 / (times.last - times.first),
      'interval_p50_us': intervals.isEmpty
          ? 0
          : intervals[intervals.length ~/ 2],
      'interval_p95_us': intervals.isEmpty
          ? 0
          : intervals[(intervals.length * .95).floor()],
      'raster_mean_us': timings.isEmpty
          ? 0
          : timings.fold<int>(
                  0,
                  (sum, t) => sum + t.rasterDuration.inMicroseconds,
                ) /
                timings.length,
    };
    binding.reportData = {'native_cadence': report};
    debugPrint('AETHERIA_CADENCE ${jsonEncode(report)}');
    controller.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(times.length, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff152534), BlendMode.src);
    canvas.drawRect(
      Rect.fromLTWH(
        animation.value * (size.width - 80),
        40,
        80,
        size.height - 80,
      ),
      Paint()..color = const Color(0xff75edb3),
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}
