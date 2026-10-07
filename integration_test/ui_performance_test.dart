import 'dart:async';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/player/ui/play_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/ui_test_fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final mobile in [false, true]) {
    testWidgets(
      'scroll 5000 songs with playback clock (${mobile ? 'mobile' : 'desktop'})',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final library = TestLibrary()
          ..songs = List.generate(5000, (i) => testSong('$i'));
        final audio = TestAudio()..playingSong = library.songs.first;
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
              home: Center(
                child: SizedBox(
                  width: mobile ? 430 : 1280,
                  child: mobile
                      ? const MobileLayout()
                      : const Scaffold(
                          body: Column(
                            children: [
                              Expanded(child: SongTable()),
                              PlayBar(),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        var ticks = 0;
        final clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
          audio.positionListenable.value = Duration(
            milliseconds: ++ticks * 250,
          );
        });
        final readsBefore = library.displayReads;
        try {
          await binding.watchPerformance(() async {
            for (var i = 0; i < 12; i++) {
              await tester.timedDrag(
                find.byType(ListView).first,
                Offset(0, i.isEven ? -420 : 420),
                const Duration(milliseconds: 400),
              );
              await tester.pumpAndSettle();
            }
          }, reportKey: mobile ? 'mobile_scroll' : 'desktop_scroll');
          expect(library.displayReads, readsBefore);
          expect(tester.takeException(), isNull);
        } finally {
          clock.cancel();
          await tester.pumpWidget(const SizedBox.shrink());
          audio.dispose();
          library.dispose();
          theme.dispose();
        }
      },
    );
  }
}
