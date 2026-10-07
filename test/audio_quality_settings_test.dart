import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AudioApi extends Fake implements RustLibApi {
  @override
  Future<void> crateApiMusicStopRustPlayback() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _AudioApi()));
  tearDownAll(RustLib.dispose);

  for (final saved in <String?>[null, 'standard', 'high']) {
    test('resampler default respects saved preference $saved', () async {
      SharedPreferences.setMockInitialValues({'resampler-quality': ?saved});
      final audio = AudioPlayerProvider();
      await audio.loadSettings();
      expect(audio.resamplerQuality, saved ?? 'high');
      audio.dispose();
    });
  }

  testWidgets(
    'output view distinguishes stream format from hardware fidelity',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final audio = AudioPlayerProvider();
      final theme = UIThemeProvider();
      await audio.loadSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsAudioOutputInfoView(
                cfg: theme.currentTheme,
                audioProvider: audio,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('应用输出: '), findsOneWidget);
      expect(find.textContaining('不能据此确认逐位无损'), findsOneWidget);
      expect(find.textContaining('输出波形会与原始音频不同'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      audio.dispose();
      theme.dispose();
    },
  );
}
