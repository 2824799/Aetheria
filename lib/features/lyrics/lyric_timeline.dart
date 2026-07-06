import 'dart:math' as math;

class LyricTimeline {
  const LyricTimeline({required this.lines, required this.translationByTime});

  final List<LyricLine> lines;
  final Map<int, String> translationByTime;

  bool get hasTimedLines => lines.any((line) => line.timeMs != null);

  static LyricTimeline parse({required String content, String? translation}) {
    return LyricTimeline(
      lines: parseLines(content),
      translationByTime: parseTranslationByTime(translation),
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
        translation: _translationFor(first),
        nextLine: lines.length > 1 ? lines[1].text : '',
        progress: 0,
        activeIndex: 0,
      );
    }

    final line = lines[activeIndex];
    return LyricFrame(
      line: line.text,
      translation: _translationFor(line),
      nextLine: activeIndex + 1 < lines.length
          ? lines[activeIndex + 1].text
          : '',
      progress: lineProgress(line, positionMs),
      activeIndex: activeIndex,
    );
  }

  String _translationFor(LyricLine line) {
    final time = line.timeMs;
    if (time == null) {
      return '';
    }
    return translationByTime[time]?.trim() ?? '';
  }

  static List<LyricLine> parseLines(String content) {
    final timedLines = <LyricLine>[];
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

    timedLines.sort((a, b) => (a.timeMs ?? 0).compareTo(b.timeMs ?? 0));
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
    for (final line in parseLines(content)) {
      final time = line.timeMs;
      if (time != null && line.text.trim().isNotEmpty) {
        result[time] = line.text;
      }
    }
    return result;
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
  LyricLine(this.timeMs, this.endMs, this.text, this.segments);

  final int? timeMs;
  int? endMs;
  final String text;
  final List<LyricSegment> segments;
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
