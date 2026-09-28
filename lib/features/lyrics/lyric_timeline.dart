import 'dart:math' as math;

class LyricTimeline {
  const LyricTimeline({required this.lines, required this.translationByTime});

  final List<LyricLine> lines;
  final Map<int, String> translationByTime;

  bool get hasTimedLines => lines.any((line) => line.timeMs != null);

  static LyricTimeline parse({required String content, String? translation}) {
    final lines = parseLines(content);
    return LyricTimeline(
      lines: lines,
      translationByTime: <int, String>{
        for (final line in lines)
          if (line.translation != null) line.timeMs!: line.translation!,
        ...parseTranslationByTime(translation),
      },
    );
  }

  LyricFrame frameAt(int positionMs) {
    if (lines.isEmpty) {
      return const LyricFrame.empty();
    }
    final activeIndex = hasTimedLines
        ? activeLineIndex(lines, positionMs)
        : math.min(0, lines.length - 1);
    if (activeIndex < 0) {
      final first = lines.first;
      return LyricFrame(
        line: first.text,
        translation: translationFor(first),
        nextLine: lines.length > 1 ? lines[1].text : '',
        progress: 0,
        activeIndex: 0,
      );
    }

    final line = lines[activeIndex];
    return LyricFrame(
      line: line.text,
      translation: translationFor(line),
      nextLine: activeIndex + 1 < lines.length
          ? lines[activeIndex + 1].text
          : '',
      progress: lineProgress(line, positionMs),
      activeIndex: activeIndex,
    );
  }

  String translationFor(LyricLine line) {
    final time = line.timeMs;
    if (time == null) {
      return '';
    }
    final explicit = translationByTime[time]?.trim() ?? '';
    return explicit.isNotEmpty ? explicit : line.translation?.trim() ?? '';
  }

  static List<LyricLine> parseLines(String content) =>
      _parseLines(content, mergeEmbeddedTranslations: true);

  static List<LyricLine> _parseLines(
    String content, {
    required bool mergeEmbeddedTranslations,
  }) {
    var timedLines = <LyricLine>[];
    final plainLines = <LyricLine>[];
    final timeReg = RegExp(
      r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?(?:,\d{1,8})?\]',
    );
    final qrcLineReg = RegExp(r'^\[(\d{1,8}),(\d{1,8})\]');
    final metadataReg = RegExp(r'^\[[a-zA-Z]+:.*\]$');

    for (final rawLine
        in content
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')) {
      if (metadataReg.hasMatch(rawLine.trim())) {
        continue;
      }
      final matches = timeReg.allMatches(rawLine).toList(growable: false);
      final qrcMatch = qrcLineReg.firstMatch(rawLine.trimLeft());
      final lineTimes = <_LineTime>[];

      for (final match in matches) {
        lineTimes.add(
          _LineTime(
            _parseTimestamp(match.group(1), match.group(2), match.group(3)),
            null,
          ),
        );
      }
      if (qrcMatch != null) {
        final start = int.tryParse(qrcMatch.group(1) ?? '') ?? 0;
        final duration = int.tryParse(qrcMatch.group(2) ?? '') ?? 0;
        lineTimes.add(_LineTime(start, duration > 0 ? start + duration : null));
      }

      final lyricPart = rawLine
          .replaceAll(timeReg, '')
          .replaceAll(qrcLineReg, '')
          .trim();
      if (lineTimes.isEmpty) {
        if (rawLine.trim().isNotEmpty) {
          plainLines.add(
            LyricLine(null, null, _cleanLyricText(rawLine), const []),
          );
        }
        continue;
      }

      for (final lineTime in lineTimes) {
        final parsed = _parseTimedLineContent(
          lyricPart,
          lineTime.startMs,
          lineTime.endMs,
        );
        timedLines.add(
          LyricLine(
            lineTime.startMs,
            lineTime.endMs,
            parsed.text,
            parsed.segments,
          ),
        );
      }
    }

    if (timedLines.isEmpty) {
      return plainLines.isEmpty ? const <LyricLine>[] : plainLines;
    }

    timedLines = _groupTimedLines(
      timedLines,
      mergeEmbeddedTranslations: mergeEmbeddedTranslations,
    );
    for (var i = 0; i < timedLines.length; i++) {
      final line = timedLines[i];
      final start = line.timeMs;
      if (start == null) {
        continue;
      }
      final nextStart = i + 1 < timedLines.length
          ? timedLines[i + 1].timeMs
          : null;
      line.endMs ??= nextStart ?? start + _estimatedLineDuration(line.text);
      if (line.endMs! <= start) {
        line.endMs = start + _estimatedLineDuration(line.text);
      }
      for (var j = 0; j < line.segments.length; j++) {
        final segment = line.segments[j];
        if (segment.endMs <= segment.startMs) {
          segment.endMs = j + 1 < line.segments.length
              ? line.segments[j + 1].startMs
              : line.endMs!;
        }
      }
    }
    return timedLines;
  }

  static Map<int, String> parseTranslationByTime(String? content) {
    if (content == null || content.trim().isEmpty) {
      return const <int, String>{};
    }
    final result = <int, String>{};
    for (final line in _parseLines(content, mergeEmbeddedTranslations: false)) {
      final time = line.timeMs;
      if (time != null && line.text.trim().isNotEmpty) {
        result[time] = line.text;
      }
    }
    return result;
  }

  // Some LRC files contain a full original track followed by a translation
  // track in the same text. Match their timestamps before sorting so the
  // first occurrence remains the primary lyric even for non-interleaved files.
  static List<LyricLine> _groupTimedLines(
    List<LyricLine> lines, {
    required bool mergeEmbeddedTranslations,
  }) {
    final byTime = <int, List<LyricLine>>{};
    for (final line in lines) {
      byTime.putIfAbsent(line.timeMs!, () => <LyricLine>[]).add(line);
    }
    final hasJapaneseTranslation = byTime.values.any((group) {
      if (group.length != 2) {
        return false;
      }
      return _scriptFamily(group[0].text) == _LyricScript.japanese &&
          _scriptFamily(group[1].text) == _LyricScript.han;
    });

    final result = <LyricLine>[];
    final times = byTime.keys.toList()..sort();
    for (final time in times) {
      final group = byTime[time]!;
      if (!mergeEmbeddedTranslations ||
          group.length != 2 ||
          group[0].text.isEmpty ||
          group[1].text.isEmpty ||
          group[0].text == group[1].text) {
        result.addAll(group);
        continue;
      }

      final firstScript = _scriptFamily(group[0].text);
      final secondScript = _scriptFamily(group[1].text);
      final differentScripts =
          firstScript != secondScript &&
          firstScript != _LyricScript.other &&
          secondScript != _LyricScript.other;
      // Kana in other timestamp pairs identifies the original Japanese
      // track, including short lines written entirely in kanji.
      final japaneseKanjiPair =
          hasJapaneseTranslation &&
          firstScript == _LyricScript.han &&
          secondScript == _LyricScript.han;
      if (!differentScripts && !japaneseKanjiPair) {
        result.addAll(group);
        continue;
      }

      final original = group[0];
      final translation = group[1];
      result.add(
        LyricLine(
          original.timeMs,
          original.endMs,
          original.text,
          original.segments,
          translation: translation.text,
        ),
      );
    }
    return result;
  }

  static _LyricScript _scriptFamily(String text) {
    var han = false;
    var latin = false;
    for (final rune in text.runes) {
      if ((rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0xff66 && rune <= 0xff9f)) {
        return _LyricScript.japanese;
      }
      if (rune >= 0xac00 && rune <= 0xd7af) {
        return _LyricScript.korean;
      }
      if ((rune >= 0x3400 && rune <= 0x4dbf) ||
          (rune >= 0x4e00 && rune <= 0x9fff) ||
          (rune >= 0xf900 && rune <= 0xfaff)) {
        han = true;
      } else if ((rune >= 0x0041 && rune <= 0x005a) ||
          (rune >= 0x0061 && rune <= 0x007a) ||
          (rune >= 0x00c0 && rune <= 0x024f)) {
        latin = true;
      }
    }
    if (han) {
      return _LyricScript.han;
    }
    return latin ? _LyricScript.latin : _LyricScript.other;
  }

  static int activeLineIndex(List<LyricLine> lines, int positionMs) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final time = lines[i].timeMs;
      if (time == null) {
        continue;
      }
      if (time <= positionMs) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  static double lineProgress(LyricLine line, int positionMs) {
    final start = line.timeMs;
    final end = line.endMs;
    if (start == null || end == null || end <= start) {
      return 0;
    }

    if (line.segments.isEmpty) {
      return ((positionMs - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    }

    var completedRunes = 0;
    final totalRunes = math.max(1, line.text.runes.length);
    for (final segment in line.segments) {
      final segmentRunes = math.max(1, segment.text.runes.length);
      if (positionMs >= segment.endMs) {
        completedRunes += segmentRunes;
        continue;
      }
      if (positionMs > segment.startMs) {
        final duration = math.max(1, segment.endMs - segment.startMs);
        final local = ((positionMs - segment.startMs) / duration).clamp(
          0.0,
          1.0,
        );
        completedRunes += (segmentRunes * local).round();
      }
      break;
    }
    return (completedRunes / totalRunes).clamp(0.0, 1.0).toDouble();
  }

  static int _parseTimestamp(
    String? minuteText,
    String? secondText,
    String? fracText,
  ) {
    final minute = int.tryParse(minuteText ?? '') ?? 0;
    final second = int.tryParse(secondText ?? '') ?? 0;
    final frac = fracText ?? '0';
    final millis = frac.length == 1
        ? int.parse(frac) * 100
        : frac.length == 2
        ? int.parse(frac) * 10
        : int.parse(frac.substring(0, math.min(3, frac.length)));
    return (minute * 60 + second) * 1000 + millis;
  }

  static int _estimatedLineDuration(String text) {
    return math.max(1800, math.min(6200, text.runes.length * 180));
  }

  static _ParsedLineContent _parseTimedLineContent(
    String rawText,
    int lineStartMs,
    int? lineEndMs,
  ) {
    final relativeReg = RegExp(r'[\(<](\d{1,8}),(\d{1,8})[\)>]');
    final absoluteReg = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');

    final relativeMatches = relativeReg
        .allMatches(rawText)
        .toList(growable: false);
    if (relativeMatches.isNotEmpty) {
      final segments = <LyricSegment>[];
      for (var i = 0; i < relativeMatches.length; i++) {
        final match = relativeMatches[i];
        final nextStart = i + 1 < relativeMatches.length
            ? relativeMatches[i + 1].start
            : rawText.length;
        final text = _cleanLyricText(rawText.substring(match.end, nextStart));
        if (text.isEmpty) {
          continue;
        }
        final offset = int.tryParse(match.group(1) ?? '') ?? 0;
        final duration = int.tryParse(match.group(2) ?? '') ?? 0;
        final start = lineStartMs + offset;
        segments.add(LyricSegment(start, start + duration, text));
      }
      final text = segments.map((segment) => segment.text).join();
      if (text.trim().isNotEmpty) {
        return _ParsedLineContent(text.trim(), segments);
      }
    }

    final absoluteMatches = absoluteReg
        .allMatches(rawText)
        .toList(growable: false);
    if (absoluteMatches.isNotEmpty) {
      final segments = <LyricSegment>[];
      for (var i = 0; i < absoluteMatches.length; i++) {
        final match = absoluteMatches[i];
        final nextStart = i + 1 < absoluteMatches.length
            ? absoluteMatches[i + 1].start
            : rawText.length;
        final text = _cleanLyricText(rawText.substring(match.end, nextStart));
        if (text.isEmpty) {
          continue;
        }
        final start = _parseTimestamp(
          match.group(1),
          match.group(2),
          match.group(3),
        );
        segments.add(LyricSegment(start, start, text));
      }
      final text = segments.map((segment) => segment.text).join();
      if (text.trim().isNotEmpty) {
        return _ParsedLineContent(text.trim(), segments);
      }
    }

    return _ParsedLineContent(_cleanLyricText(rawText), const []);
  }

  static String _cleanLyricText(String text) {
    return text
        .replaceAll(RegExp(r'\[[a-zA-Z]+:[^\]]*\]'), '')
        .replaceAll(RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>'), '')
        .replaceAll(RegExp(r'[\(<](\d{1,8}),(\d{1,8})[\)>]'), '')
        .trim();
  }
}

class LyricFrame {
  const LyricFrame({
    required this.line,
    required this.translation,
    required this.nextLine,
    required this.progress,
    required this.activeIndex,
  });

  const LyricFrame.empty()
    : line = '',
      translation = '',
      nextLine = '',
      progress = 0,
      activeIndex = -1;

  final String line;
  final String translation;
  final String nextLine;
  final double progress;
  final int activeIndex;
}

class LyricLine {
  LyricLine(
    this.timeMs,
    this.endMs,
    this.text,
    this.segments, {
    this.translation,
  });

  final int? timeMs;
  int? endMs;
  final String text;
  final List<LyricSegment> segments;
  final String? translation;
}

class LyricSegment {
  LyricSegment(this.startMs, this.endMs, this.text);

  final int startMs;
  int endMs;
  final String text;
}

class _LineTime {
  const _LineTime(this.startMs, this.endMs);

  final int startMs;
  final int? endMs;
}

class _ParsedLineContent {
  const _ParsedLineContent(this.text, this.segments);

  final String text;
  final List<LyricSegment> segments;
}

enum _LyricScript { japanese, korean, han, latin, other }
