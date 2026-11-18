import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/features/player/ui/play_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

void main() {
  testWidgets(
    'PlayBar throttles playback ticks and updates immediately when paused',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 120));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final theme = UIThemeProvider();
      final library = TestLibrary();
      final audio = TestAudio()
        ..isPlaying = true
        ..totalDuration = const Duration(seconds: 100);
      audio.playingSong = testSong('track');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ],
          child: MaterialApp(
            theme: theme.themeData,
            home: const Scaffold(body: PlayBar()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('00:00 / 01:40'), findsOneWidget);
      final initialTextWidget = tester.widget<Text>(find.text('00:00 / 01:40'));
      expect(
        tester.widget<AetherSeekBar>(find.byType(AetherSeekBar)).progress,
        0.0,
      );

      // Sub-250ms tick while playing holds both the 250ms seekbar and 1s label.
      audio.positionListenable.value = const Duration(milliseconds: 100);
      await tester.pump();
      expect(
        identical(
          tester.widget<Text>(find.text('00:00 / 01:40')),
          initialTextWidget,
        ),
        isTrue,
      );
      expect(
        tester.widget<AetherSeekBar>(find.byType(AetherSeekBar)).progress,
        0.0,
      );

      // Crossing 250ms updates the seekbar while holding the 1s label until 1s.
      audio.positionListenable.value = const Duration(milliseconds: 300);
      await tester.pump();
      expect(
        identical(
          tester.widget<Text>(find.text('00:00 / 01:40')),
          initialTextWidget,
        ),
        isTrue,
      );
      expect(
        tester.widget<AetherSeekBar>(find.byType(AetherSeekBar)).progress,
        closeTo(0.003, 1e-6),
      );

      // Whole-second label updates once the second rolls over cleanly.
      audio.positionListenable.value = const Duration(milliseconds: 1100);
      await tester.pump();
      expect(find.text('00:01 / 01:40'), findsOneWidget);
      expect(
        tester.widget<AetherSeekBar>(find.byType(AetherSeekBar)).progress,
        closeTo(0.011, 1e-6),
      );

      // While paused, sub-250ms seeks update seekbar immediately while keeping 1s text.
      await audio.playPause();
      await tester.pump();
      final secondTextWidget = tester.widget<Text>(find.text('00:01 / 01:40'));
      audio.positionListenable.value = const Duration(milliseconds: 1200);
      await tester.pump();
      expect(
        identical(
          tester.widget<Text>(find.text('00:01 / 01:40')),
          secondTextWidget,
        ),
        isTrue,
      );
      expect(
        tester.widget<AetherSeekBar>(find.byType(AetherSeekBar)).progress,
        closeTo(0.012, 1e-6),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      audio.dispose();
      library.dispose();
      theme.dispose();
    },
  );
}
