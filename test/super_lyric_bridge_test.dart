import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:aetheria/features/lyrics/super_lyric_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildSuperLyricPayload maps timing, offset, words and secondary text',
    () {
      final line = LyricLine(1000, 2200, '你好', <LyricSegment>[
        LyricSegment(1100, 1500, '你'),
        LyricSegment(1500, 2100, '好'),
      ]);

      final payload = buildSuperLyricPayload(
        title: '测试歌曲',
        artist: '测试歌手',
        album: '测试专辑',
        line: line,
        translation: 'Hello',
        secondary: 'Ni hao',
        offsetMs: 200,
      );

      expect(payload['title'], '测试歌曲');
      expect(payload['artist'], '测试歌手');
      expect(payload['album'], '测试专辑');
      expect(payload['line'], '你好');
      expect(payload['startTimeMs'], 800);
      expect(payload['endTimeMs'], 2000);
      expect(payload['translation'], 'Hello');
      expect(payload['secondary'], 'Ni hao');
      expect(payload['words'], <Map<String, dynamic>>[
        <String, dynamic>{'text': '你', 'startTimeMs': 900, 'endTimeMs': 1300},
        <String, dynamic>{'text': '好', 'startTimeMs': 1300, 'endTimeMs': 1900},
      ]);
    },
  );

  test('buildSuperLyricPayload keeps untimed lyrics text-only', () {
    final payload = buildSuperLyricPayload(
      title: '纯文本',
      line: LyricLine(null, null, '第一行', const <LyricSegment>[]),
    );

    expect(payload['line'], '第一行');
    expect(payload, isNot(contains('startTimeMs')));
    expect(payload, isNot(contains('endTimeMs')));
    expect(payload, isNot(contains('words')));
    expect(payload, isNot(contains('translation')));
    expect(payload, isNot(contains('secondary')));
  });

  test('timed empty lines hold the current SuperLyric instead of stopping', () {
    final timeline = LyricTimeline.parse(
      content: '''
[00:17.063]In fading poems, frozen rhymes
[00:21.009]
[00:21.186]
[00:21.447]Our traces on the breeze
[01:21.104]
[01:51.036]Please, stay true
''',
    );

    final firstGap =
        timeline.lines[LyricTimeline.activeLineIndex(timeline.lines, 21100)];
    final secondGap =
        timeline.lines[LyricTimeline.activeLineIndex(timeline.lines, 21200)];
    final resumed =
        timeline.lines[LyricTimeline.activeLineIndex(timeline.lines, 21447)];
    final longGap =
        timeline.lines[LyricTimeline.activeLineIndex(timeline.lines, 100000)];
    final resumedAfterLongGap =
        timeline.lines[LyricTimeline.activeLineIndex(timeline.lines, 111036)];

    expect(shouldHoldSuperLyricLine(firstGap), isTrue);
    expect(shouldHoldSuperLyricLine(secondGap), isTrue);
    expect(shouldHoldSuperLyricLine(longGap), isTrue);
    expect(resumed.text, 'Our traces on the breeze');
    expect(shouldHoldSuperLyricLine(resumed), isFalse);
    expect(resumedAfterLongGap.text, 'Please, stay true');
    expect(shouldHoldSuperLyricLine(resumedAfterLongGap), isFalse);
  });
}
