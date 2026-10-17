import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/settings/settings_floating_lyrics_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';
import 'package:aetheria/features/lyrics/floating_lyrics_bridge.dart';
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
}
