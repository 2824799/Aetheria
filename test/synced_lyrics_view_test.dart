import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_synced_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _original = '''
[00:01.000]A bright morning
[00:02.000]Open the window
''';
const _translation = '''
[00:01.000]明亮的早晨
[00:02.000]打开窗户
''';

void main() {
  for (final embedded in <bool>[true, false]) {
    testWidgets('bilingual text shares one active lyric tile ($embedded)', (
      tester,
    ) async {
      final audio = _TestAudioPlayer();
      addTearDown(audio.dispose);
      await tester.pumpWidget(
        _view(
          audio,
          content: embedded ? '$_original\n$_translation' : _original,
          translation: embedded ? null : _translation,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LyricLineTile), findsNWidgets(2));
      final firstTile = find.ancestor(
        of: find.text('A bright morning'),
        matching: find.byType(LyricLineTile),
      );
      expect(
        find.descendant(of: firstTile, matching: find.text('明亮的早晨')),
        findsOneWidget,
      );
      expect(tester.widget<LyricLineTile>(firstTile).active, isTrue);
      final verticalGap =
          tester.getTopLeft(find.text('明亮的早晨')).dy -
          tester.getTopLeft(find.text('A bright morning')).dy;
      expect(verticalGap, inExclusiveRange(0, 30));

      audio.setPosition(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      final secondTile = find.ancestor(
        of: find.text('Open the window'),
        matching: find.byType(LyricLineTile),
      );
      expect(tester.widget<LyricLineTile>(secondTile).active, isTrue);
      expect(
        find.descendant(of: secondTile, matching: find.text('打开窗户')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ticks within one lyric line do not rebuild its tiles', (
    tester,
  ) async {
    final audio = _TestAudioPlayer();
    addTearDown(audio.dispose);
    await tester.pumpWidget(_view(audio, content: _original));
    await tester.pumpAndSettle();
    final tile = tester.widget<LyricLineTile>(find.byType(LyricLineTile).first);
    audio.setPosition(const Duration(milliseconds: 1750));
    await tester.pump();
    expect(
      identical(
        tile,
        tester.widget<LyricLineTile>(find.byType(LyricLineTile).first),
      ),
      isTrue,
    );
    audio.setPosition(const Duration(milliseconds: 2250));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LyricLineTile>(find.byType(LyricLineTile).last).active,
      isTrue,
    );
  });

  testWidgets('replacing lyric content refreshes the cached timeline', (
    tester,
  ) async {
    final audio = _TestAudioPlayer();
    addTearDown(audio.dispose);
    await tester.pumpWidget(_view(audio, content: _original));
    await tester.pumpAndSettle();
    expect(find.text('明亮的早晨'), findsNothing);

    await tester.pumpWidget(
      _view(audio, content: _original, translation: _translation),
    );
    await tester.pumpAndSettle();
    expect(find.text('明亮的早晨'), findsOneWidget);

    await tester.pumpWidget(
      _view(audio, content: '[00:01.000]Another sentence\n[00:01.000]另一句话'),
    );
    await tester.pumpAndSettle();
    expect(find.text('A bright morning'), findsNothing);
    expect(find.text('明亮的早晨'), findsNothing);
    expect(find.text('Another sentence'), findsOneWidget);
    expect(find.text('另一句话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _view(
  AudioPlayerProvider audio, {
  required String content,
  String? translation,
}) {
  return ChangeNotifierProvider<AudioPlayerProvider>.value(
    value: audio,
    child: MaterialApp(
      theme: buildAetheriaThemeData(AppThemeConfig.pink),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 560,
            height: 420,
            child: SyncedLyricsView(
              content: content,
              translation: translation,
              offsetMs: 0,
              cfg: AppThemeConfig.pink,
              compact: true,
              allowSeekGuide: false,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TestAudioPlayer extends ChangeNotifier implements AudioPlayerProvider {
  @override
  final ValueNotifier<Duration> positionListenable = ValueNotifier(
    const Duration(milliseconds: 1500),
  );

  @override
  Duration get currentPosition => positionListenable.value;

  void setPosition(Duration position) {
    positionListenable.value = position;
  }

  @override
  void dispose() {
    positionListenable.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
