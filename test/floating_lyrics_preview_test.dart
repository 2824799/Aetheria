import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/features/lyrics/floating_lyrics_bridge.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_test_fakes.dart';

const _lyrics = '''
[00:01.000]明るい朝です
[00:01.000]明亮的早晨
[00:02.000]窓を開けて
[00:02.000]打开窗户
[00:03.000]風を感じて
[00:03.000]感受微风
''';

void main() {
  for (final compact in [false, true]) {
    testWidgets(
      'native previews pair translations without duplicates ($compact)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = FloatingLyricsProvider();
        await settings.load();
        await settings.setEnabled(true);
        await settings.setCompactMultiline(compact);
        final audio = TestAudio()
          ..isPlaying = true
          ..playingSong = const Song(
            id: 'bilingual-preview',
            title: 'Bilingual preview',
            lyrics: _lyrics,
            rating: 0,
            createdAt: '',
            versions: [],
            tags: [],
          );
        audio.positionListenable.value = const Duration(milliseconds: 1500);
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
        expect(frames.last['line'], '明るい朝です');
        expect(frames.last['translation'], '明亮的早晨');
        expect(frames.last['nextLine'], '窓を開けて');
        expect(frames.last['nextTranslation'], '打开窗户');
        expect(frames.last['contextLines'], compact ? ['風を感じて'] : []);
        expect(frames.last['contextTranslations'], compact ? ['感受微风'] : []);

        await settings.setShowTranslation(false);
        await tester.pump();
        await audio.playPause();
        await tester.pump();
        expect(frames.last['translation'], '');
        expect(frames.last['nextTranslation'], '');
        expect(frames.last['contextTranslations'], compact ? [''] : []);

        await settings.setShowTranslation(true);
        await tester.pump();
        audio.positionListenable.value = const Duration(milliseconds: 2500);
        await audio.playPause();
        await tester.pump();
        expect(frames.last['line'], '窓を開けて');
        expect(frames.last['translation'], '打开窗户');
        expect(frames.last['nextLine'], '風を感じて');
        expect(frames.last['nextTranslation'], '感受微风');
        expect(frames.last['contextLines'], isEmpty);
        expect(frames.last['contextTranslations'], isEmpty);

        await settings.setShowNextLine(false);
        await tester.pump();
        await audio.playPause();
        await tester.pump();
        expect(frames.last['nextLine'], '');
        expect(frames.last['nextTranslation'], '');
        await settings.setShowNextLine(true);
        await tester.pump();
        audio.positionListenable.value = const Duration(milliseconds: 3500);
        await audio.playPause();
        await tester.pump();
        expect(frames.last['line'], '風を感じて');
        expect(frames.last['nextLine'], '');
        expect(frames.last['nextTranslation'], '');
        expect(frames.last['contextLines'], isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        settings.dispose();
        audio.dispose();
      },
    );
  }
}
