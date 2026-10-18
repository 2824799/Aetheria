import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('drawer responds to close and reversal (reduced=$reduced)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final library = TestLibrary()..songs = [testSong('0'), testSong('1')];
      final audio = TestAudio()..activeSong = library.songs.first;
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
          child: MaterialApp(
            theme: theme.themeData,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: const MainLayout(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      audio.setDetailOpen(true);
      await tester.pumpAndSettle();
      double x() => tester.getTopLeft(find.byType(DetailPane)).dx;
      final openX = x();
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pump();
      if (reduced) {
        expect(find.byType(DetailPane), findsNothing);
      } else {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          x() - openX,
          greaterThan(60),
          reason: 'Closing must move visibly within the first frame',
        );
        final closingX = x();
        // The closing barrier must immediately release the list so a new row
        // click can reverse the animation, even before the old panel exits.
        await tester.tap(find.text('Track 1').first);
        await tester.pump();
        expect(audio.isDetailOpen, isTrue);
        expect(audio.activeSong?.id, '1');
        expect(
          x(),
          closeTo(closingX, .01),
          reason: 'Reversing must preserve the current visible position',
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(x(), lessThan(closingX - 10));
        // Interrupt opening too: no restart, position jump or slow start.
        final openingX = x();
        audio.setDetailOpen(false);
        await tester.pump();
        expect(x(), closeTo(openingX, .01));
        await tester.pump(const Duration(milliseconds: 16));
        expect(x(), greaterThan(openingX + 20));
        await tester.pump(const Duration(milliseconds: 130));
        expect(find.byType(DetailPane), findsNothing);
        expect(
          find.descendant(
            of: find.byType(MainLayout),
            matching: find.byType(ModalBarrier),
          ),
          findsNothing,
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
}
