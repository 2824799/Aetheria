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

  testWidgets('wheel starts within one frame and brakes within 100ms', (
    tester,
  ) async {
    final c = await mount(tester);
    c.position.pointerScroll(100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6));
    expect(c.offset, greaterThan(10));
    expect(c.offset, lessThan(100));
    await tester.pump(const Duration(milliseconds: 95));
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
      expect(400 - c.offset, lessThanOrEqualTo(104));
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
