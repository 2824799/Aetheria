// Probe the production painter so thumb gestures respect its actual hit area.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:ui' show PointerDeviceKind;

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

void main() {
  testWidgets('600-song thumb stays visible and preserves its track geometry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Also cover the desktop FittedBox and horizontal table overflow.
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = TestLibrary()
      ..songs = List.generate(600, (i) => testSong('$i'))
      ..tags = const [
        Tag(id: 1, name: '日语'),
        Tag(id: 2, name: '中文'),
        Tag(id: 3, name: '收藏'),
        Tag(id: 4, name: '音乐'),
      ];
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
    final table = find.byType(SongTable);
    final list = find.descendant(of: table, matching: find.byType(ListView));
    final controller = tester.widget<ListView>(list).controller!;
    final bar = find.descendant(
      of: table,
      matching: find.byWidgetPredicate(
        (w) => w is RawScrollbar && w.controller == controller,
      ),
    );
    expect(
      bar,
      findsOneWidget,
      reason: 'Only one vertical scrollbar should observe the list',
    );
    final state = tester.state<RawScrollbarState>(bar);
    final box = tester.renderObject<RenderBox>(bar);
    final painter = state.scrollbarPainter;
    final thumbX =
        box.size.width -
        painter.crossAxisMargin -
        (painter.padding.resolve(TextDirection.ltr).right) -
        painter.thickness / 2;
    final y = List.generate(box.size.height.floor(), (i) => i.toDouble())
        .firstWhere(
          (y) => painter.hitTestOnlyThumbInteractive(
            Offset(thumbX, y),
            PointerDeviceKind.mouse,
          ),
        );
    final start = box.localToGlobal(Offset(thumbX, y + 8));
    final height = tester.getRect(list).height;
    final tableBounds = tester.getRect(table);
    expect(start.dx, lessThanOrEqualTo(tableBounds.right));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    final end = box.localToGlobal(Offset(thumbX, box.size.height - 45));
    for (var pass = 0; pass < 3; pass++) {
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(start, end, step / 20)!);
        await tester.pump(const Duration(microseconds: 6061));
        if (step > 1 && step < 19) {
          expect(
            painter.hitTestOnlyThumbInteractive(
              box.globalToLocal(Offset.lerp(start, end, step / 20)!),
              PointerDeviceKind.mouse,
            ),
            isTrue,
            reason: 'The thumb must reach the pointer within this frame',
          );
        }
      }
      expect(
        controller.offset,
        greaterThan(controller.position.maxScrollExtent * .85),
      );
      expect(
        tester.getRect(list).height,
        height,
        reason: 'Collapsing tags during a thumb drag moves its track',
      );
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(end, start, step / 20)!);
        await tester.pump(const Duration(microseconds: 6061));
      }
      expect(controller.offset, lessThan(1));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(audio.isDetailOpen, isFalse);
    expect(audio.activeSong, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    audio.dispose();
    library.dispose();
    theme.dispose();
    sync.dispose();
  });
}
