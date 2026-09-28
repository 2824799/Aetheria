import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges an embedded translation track by matching timestamps', () {
    final timeline = LyricTimeline.parse(
      content: '''
[ti:Test song]
[00:25.226]A bright morning
[00:30.873]Open the window
[00:25.226]明亮的早晨
[00:30.873]打开窗户
''',
    );

    expect(timeline.lines, hasLength(2));
    expect(timeline.lines[0].text, 'A bright morning');
    expect(timeline.lines[0].endMs, 30873);
    expect(timeline.lines[1].text, 'Open the window');
    expect(timeline.translationByTime, <int, String>{
      25226: '明亮的早晨',
      30873: '打开窗户',
    });

    final frame = timeline.frameAt(26000);
    expect(frame.line, 'A bright morning');
    expect(frame.translation, '明亮的早晨');
    expect(frame.nextLine, 'Open the window');
    expect(frame.activeIndex, 0);
    expect(frame.progress, closeTo((26000 - 25226) / (30873 - 25226), 0.0001));
    expect(timeline.frameAt(31000).line, 'Open the window');
    expect(timeline.frameAt(31000).translation, '打开窗户');
  });

  test('keeps a source supplied translation aligned by timestamp', () {
    final timeline = LyricTimeline.parse(
      content: '''
[00:01.000]A bright morning
[00:02.000]Open the window
''',
      translation: '''
[00:01.000]明亮的早晨
[00:02.000]打开窗户
''',
    );

    expect(timeline.lines, hasLength(2));
    expect(timeline.translationFor(timeline.lines[0]), '明亮的早晨');
    expect(timeline.translationFor(timeline.lines[1]), '打开窗户');
    expect(timeline.frameAt(1500).line, 'A bright morning');
    expect(timeline.frameAt(1500).translation, '明亮的早晨');
  });

  test('does not merge same language lines with the same timestamp', () {
    final timeline = LyricTimeline.parse(
      content: '''
[00:01.000]First voice
[00:01.000]Second voice
''',
    );

    expect(timeline.lines, hasLength(2));
    expect(timeline.lines[0].text, 'First voice');
    expect(timeline.lines[1].text, 'Second voice');
    expect(timeline.translationFor(timeline.lines[0]), isEmpty);
    expect(timeline.translationFor(timeline.lines[1]), isEmpty);
  });

  test('keeps Chinese voice tracks separate even when stored in blocks', () {
    final timeline = LyricTimeline.parse(
      content: '''
[00:01.000]声部甲第一句
[00:02.000]声部甲第二句
[00:01.000]声部乙第一句
[00:02.000]声部乙第二句
''',
    );

    expect(timeline.lines.map((line) => line.text), <String>[
      '声部甲第一句',
      '声部乙第一句',
      '声部甲第二句',
      '声部乙第二句',
    ]);
    expect(timeline.translationByTime, isEmpty);
  });

  for (final interleaved in <bool>[true, false]) {
    test(
      'pairs Japanese and Chinese including kanji-only lines ($interleaved)',
      () {
        final timeline = LyricTimeline.parse(
          content: interleaved
              ? '''
[00:01.000]明るい朝です
[00:01.000]明亮的早晨
[00:02.000]朝日
[00:02.000]晨曦
'''
              : '''
[00:01.000]明るい朝です
[00:02.000]朝日
[00:01.000]明亮的早晨
[00:02.000]晨曦
''',
        );

        expect(timeline.lines, hasLength(2));
        expect(timeline.frameAt(1500).line, '明るい朝です');
        expect(timeline.frameAt(1500).translation, '明亮的早晨');
        expect(timeline.frameAt(2500).line, '朝日');
        expect(timeline.frameAt(2500).translation, '晨曦');
      },
    );
  }

  test('repeated LRC tags retain the translation at each occurrence', () {
    final timeline = LyricTimeline.parse(
      content: '''
[00:01.0][00:05.00]A bright morning
[00:01.000][00:05.0]明亮的早晨
''',
    );

    expect(timeline.lines.map((line) => line.timeMs), <int>[1000, 5000]);
    expect(timeline.frameAt(1500).translation, '明亮的早晨');
    expect(timeline.frameAt(5500).translation, '明亮的早晨');
  });

  test('merging retains the original QRC duration and word timing', () {
    final timeline = LyricTimeline.parse(
      content: '''
[1000,2400](0,400)あ(400,400)さ
[00:01.000]早晨
[00:04.000]かぜ
[00:04.000]微风
''',
    );
    final line = timeline.lines.first;

    expect(timeline.lines, hasLength(2));
    expect(line.endMs, 3400);
    expect(line.segments.map((segment) => segment.startMs), <int>[1000, 1400]);
    expect(line.segments.map((segment) => segment.endMs), <int>[1400, 1800]);
    final frame = timeline.frameAt(1400);
    expect(frame.line, 'あさ');
    expect(frame.translation, '早晨');
    expect(frame.nextLine, 'かぜ');
    expect(frame.progress, 0.5);
  });

  test(
    'explicit translation overrides embedded text and fills no blank rows',
    () {
      final timeline = LyricTimeline.parse(
        content: '''
[00:01.000]A bright morning
[00:01.000]早晨
[00:02.000]Open the window
[00:02.000]打开窗户
''',
        translation: '''
[00:01.000]明亮的早晨
[00:02.000]
''',
      );

      expect(timeline.frameAt(1500).translation, '明亮的早晨');
      expect(timeline.frameAt(2500).translation, '打开窗户');
    },
  );

  test(
    'does not interpret an explicit secondary track as bilingual content',
    () {
      final translations = LyricTimeline.parseTranslationByTime('''
[00:01.000]Earlier text
[00:01.000]修订后的译文
''');

      expect(translations, <int, String>{1000: '修订后的译文'});
    },
  );

  test(
    'leaves different timestamps and untimed bilingual text independent',
    () {
      final timed = LyricTimeline.parse(
        content: '[00:01.000]A bright morning\n[00:01.010]明亮的早晨',
      );
      expect(timed.lines, hasLength(2));
      expect(timed.translationByTime, isEmpty);

      final plain = LyricTimeline.parse(content: 'A bright morning\n明亮的早晨');
      expect(plain.lines.map((line) => line.text), <String>[
        'A bright morning',
        '明亮的早晨',
      ]);
      expect(plain.hasTimedLines, isFalse);
    },
  );
}
