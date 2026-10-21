import 'dart:math' as math;

import 'package:aetheria/features/library/ui/song_table/song_table_scroll_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SongTableScrollController> mount(WidgetTester tester) async {
    final controller = SongTableScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 52,
          itemCount: 600,
          itemBuilder: (_, i) => Text('Track $i'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('wheel starts within one frame and settles within 180ms', (
    tester,
  ) async {
    final c = await mount(tester);
    c.position.pointerScroll(100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6));
    expect(c.offset, greaterThan(1));
    expect(c.offset, lessThan(100));
    await tester.pump(const Duration(milliseconds: 174));
    expect(c.offset, closeTo(100, .01));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.offset, closeTo(100, .01));
  });

  testWidgets(
    'bursts preserve distance, reverse immediately and thumb cancels tail',
    (tester) async {
      final c = await mount(tester);
      for (var i = 0; i < 8; i++) {
        c.position.pointerScroll(50);
        await tester.pump(const Duration(milliseconds: 6));
      }
      expect(c.offset, greaterThan(0));
      expect(c.offset, lessThan(400));
      await tester.pumpAndSettle();
      expect(c.offset, closeTo(400, .01));
      c.position.pointerScroll(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 12));
      final before = c.offset;
      c.position.pointerScroll(-100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 6));
      expect(c.offset, lessThan(before));
      final hold = c.position.hold(() {});
      final held = c.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.offset, held);
      hold.cancel();
      c.position.pointerScroll(50);
      await tester.pump();
      c.jumpTo(1200);
      await tester.pumpAndSettle();
      expect(c.offset, 1200);
    },
  );

  for (final cadence in [12, 36, 60, 90, 120]) {
    testWidgets('steady ${cadence}ms wheel notches keep a continuous speed', (
      tester,
    ) async {
      final c = await mount(tester);
      const frameMs = 6;
      final framesPerNotch = cadence ~/ frameMs;
      final notches = math.max(24, (1200 / cadence).ceil());
      final speeds = <double>[];
      for (var frame = 0; frame < framesPerNotch * notches; frame++) {
        if (frame % framesPerNotch == 0) {
          final before = c.offset;
          final previous = c.position.activity;
          final velocity = previous?.velocity;
          c.position.pointerScroll(60);
          // Adding input never teleports the content or restarts its clock.
          expect(c.offset, before);
          if (frame > 0) {
            expect(c.position.activity, same(previous));
            expect(c.position.activity!.velocity, velocity);
          }
        }
        final before = c.offset;
        await tester.pump(const Duration(milliseconds: frameMs));
        final speed = (c.offset - before) / (frameMs / 1000);
        expect(speed, greaterThanOrEqualTo(0));
        if (frame * frameMs >= 800 && frame >= framesPerNotch * 16) {
          speeds.add(speed);
        }
      }
      final mean = speeds.reduce((a, b) => a + b) / speeds.length;
      final deviation = math.sqrt(
        speeds.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
            speeds.length,
      );
      final variation = deviation / mean;
      final minimum = speeds.reduce(math.min);
      final maximum = speeds.reduce(math.max);
      expect(mean, closeTo(60000 / cadence, 60000 / cadence * .03));
      expect(variation, lessThan(.12));
      expect(minimum / mean, greaterThan(.70));
      expect(maximum / mean, lessThan(1.20));
      debugPrint(
        'WHEEL_CADENCE period_ms=$cadence cv=${variation.toStringAsFixed(4)} '
        'min_ratio=${(minimum / mean).toStringAsFixed(3)} '
        'max_ratio=${(maximum / mean).toStringAsFixed(3)}',
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(c.offset, closeTo(notches * 60, .01));
      final stopped = c.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.offset, stopped);
    });
  }

  testWidgets('large and changing wheel input never jumps between frames', (
    tester,
  ) async {
    final c = await mount(tester);
    var distance = 0.0;
    for (final interval in [120, 60, 12, 6, 36, 90, 120]) {
      for (var i = 0; i < 5; i++) {
        final before = c.offset;
        c.position.pointerScroll(240);
        distance += 240;
        expect(c.offset, before);
        await tester.pump(Duration(milliseconds: interval));
        expect(c.offset, greaterThanOrEqualTo(before));
        expect(c.offset, lessThanOrEqualTo(distance));
      }
    }
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(distance, .01));
  });

  testWidgets('wheel stops at either edge and cancels on touch drag', (
    tester,
  ) async {
    final c = await mount(tester);
    c.jumpTo(c.position.maxScrollExtent - 40);
    for (var i = 0; i < 8; i++) {
      c.position.pointerScroll(120);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    expect(c.offset, c.position.maxScrollExtent);
    c.jumpTo(40);
    c.position.pointerScroll(-120);
    await tester.pumpAndSettle();
    expect(c.offset, 0);
    c.jumpTo(1000);
    c.position.pointerScroll(100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    final held = c.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.offset, held);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('trackpad and reduced motion keep native pointer scrolling', (
    tester,
  ) async {
    final c = await mount(tester);
    c.pointerKind = PointerDeviceKind.trackpad;
    c.position.pointerScroll(80);
    expect(c.offset, 80);
    c.pointerKind = PointerDeviceKind.mouse;
    c.smoothWheel = false;
    c.position.pointerScroll(80);
    expect(c.offset, 160);
  });
}
