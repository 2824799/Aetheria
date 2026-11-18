import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/settings/settings_floating_lyrics_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';
import 'package:aetheria/features/lyrics/floating_lyrics_bridge.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

void main() {
  testWidgets('pause and resume immediately update native lyrics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = FloatingLyricsProvider();
    await settings.load();
    await settings.setEnabled(true);
    await settings.setPauseOpacity(0);
    final audio = TestAudio()..isPlaying = true;
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.aetheria.app/notification');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    Map<dynamic, dynamic> lastPayload(String method) =>
        calls.lastWhere((call) => call.method == method).arguments as Map;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FloatingLyricsProvider>.value(value: settings),
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
        ],
        child: const FloatingLyricsBridge(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    expect(lastPayload('updateFloatingLyricsStyle')['pauseOpacity'], 0);
    expect(lastPayload('updateFloatingLyrics')['isPlaying'], isTrue);

    await audio.playPause();
    await tester.pump();
    expect(lastPayload('updateFloatingLyrics')['isPlaying'], isFalse);
    await settings.setPauseOpacity(0.37);
    await tester.pump();
    expect(lastPayload('updateFloatingLyricsStyle')['pauseOpacity'], 0.37);
    await audio.playPause();
    await tester.pump();
    expect(lastPayload('updateFloatingLyrics')['isPlaying'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    settings.dispose();
    audio.dispose();
  });

  testWidgets('pause opacity slider reaches 0 and 100 percent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = FloatingLyricsProvider();
    final theme = UIThemeProvider();
    await provider.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.themeData,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: provider,
              builder: (context, _) => SettingsFloatingLyricsTab(
                cfg: theme.currentTheme,
                provider: provider,
                isDesktop: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂停时降低透明度'), findsNothing);
    final row = find.ancestor(
      of: find.text('暂停时透明度'),
      matching: find.byType(SettingsSliderRow),
    );
    final slider = find.descendant(of: row, matching: find.byType(Slider));
    await tester.ensureVisible(slider);
    expect(tester.widget<Slider>(slider).divisions, 100);

    await tester.drag(slider, const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(provider.pauseOpacity, 0);
    expect(find.descendant(of: row, matching: find.text('0%')), findsOneWidget);

    await tester.drag(slider, const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(provider.pauseOpacity, 1);
    expect(
      find.descendant(of: row, matching: find.text('100%')),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('aetheria-floating-lyrics-pause-opacity'), 1);
    expect(provider.opacity, 0.95);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    theme.dispose();
  });

  testWidgets(
    'paused FloatingLyricsBridge skips polling timers and updates on paused seek',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = FloatingLyricsProvider();
      await settings.load();
      await settings.setEnabled(true);
      final audio = TestAudio()
        ..isPlaying = false
        ..playingSong = const Song(
          id: 'paused-seek',
          title: 'Paused Seek',
          lyrics: '[00:01.00]First line\n[00:05.00]Second line',
          rating: 0,
          createdAt: '',
          versions: [],
          tags: [],
        );
      audio.positionListenable.value = const Duration(milliseconds: 1200);

      final frames = <Map<dynamic, dynamic>>[];
      const channel = MethodChannel('com.aetheria.app/notification');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'updateFloatingLyrics') {
              frames.add(call.arguments as Map);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FloatingLyricsProvider>.value(
              value: settings,
            ),
            ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ],
          child: const FloatingLyricsBridge(child: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(frames, hasLength(1));
      expect(frames.single['line'], 'First line');

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(frames, hasLength(1));

      audio.positionListenable.value = const Duration(seconds: 6);
      await tester.pump();
      expect(frames, hasLength(2));
      expect(frames.last['line'], 'Second line');

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(frames, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      settings.dispose();
      audio.dispose();
    },
  );

  testWidgets(
    'playing track without timed lyrics avoids periodic floating lyric timer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = FloatingLyricsProvider();
      await settings.load();
      await settings.setEnabled(true);
      await settings.setRefreshFps(60);
      final audio = TestAudio()
        ..isPlaying = true
        ..playingSong = const Song(
          id: 'plain-track',
          title: 'Plain Track',
          lyrics: 'Untimed line 1\nUntimed line 2',
          rating: 0,
          createdAt: '',
          versions: [],
          tags: [],
        );

      final frames = <Map<dynamic, dynamic>>[];
      const channel = MethodChannel('com.aetheria.app/notification');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'updateFloatingLyrics') {
              frames.add(call.arguments as Map);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FloatingLyricsProvider>.value(
              value: settings,
            ),
            ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ],
          child: const FloatingLyricsBridge(child: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(frames, hasLength(1));
      expect(frames.single['line'], 'Untimed line 1');

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(frames, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      settings.dispose();
      audio.dispose();
    },
  );
}
