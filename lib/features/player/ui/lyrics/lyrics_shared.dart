import 'dart:math' as math;

String lyricSourceLabel(String source) {
  return switch (source) {
    'local_embedded' => '音频内嵌',
    'local_lrc' => '本地 LRC',
    'legacy_song' => '旧版歌曲歌词',
    'lrclib' => 'LRCLIB',
    'netease' => '网易云音乐',
    'qq' => 'QQ音乐',
    'kugou' => '酷狗音乐',
    'manual' => '手动保存',
    _ => source,
  };
}

const lyricsFontFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'sans-serif',
];


List<LyricLine> parseLyrics(String content) {
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
    final lineTimes = <LyricLineTime>[];
    for (final match in matches) {
      lineTimes.add(
        LyricLineTime(
          parseLyricTimestamp(match.group(1), match.group(2), match.group(3)),
          null,
        ),
      );
    }
    if (qrcMatch != null) {
      final start = int.tryParse(qrcMatch.group(1) ?? '') ?? 0;
      final duration = int.tryParse(qrcMatch.group(2) ?? '') ?? 0;
      lineTimes.add(LyricLineTime(start, duration > 0 ? start + duration : null));
    }

    var lyricPart = rawLine
        .replaceAll(timeReg, '')
        .replaceAll(qrcLineReg, '')
        .trim();
    if (lineTimes.isEmpty) {
      if (rawLine.trim().isNotEmpty) {
        plainLines.add(
          LyricLine(null, null, cleanLyricText(rawLine), const []),
        );
      }
      continue;
    }
    for (final lineTime in lineTimes) {
      final parsed = parseTimedLyricLineContent(
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
    line.endMs ??= nextStart ?? start + estimatedLyricLineDuration(line.text);
    if (line.endMs! <= start) {
      line.endMs = start + estimatedLyricLineDuration(line.text);
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

Map<int, String> translationByTime(String? content) {
  if (content == null || content.trim().isEmpty) {
    return const <int, String>{};
  }
  final result = <int, String>{};
  for (final line in parseLyrics(content)) {
    final time = line.timeMs;
    if (time != null && line.text.trim().isNotEmpty) {
      result[time] = line.text;
    }
  }
  return result;
}

int activeLyricLineIndex(List<LyricLine> lines, int positionMs) {
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

int parseLyricTimestamp(
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

int estimatedLyricLineDuration(String text) {
  return math.max(1800, math.min(6200, text.runes.length * 180));
}

ParsedLyricLineContent parseTimedLyricLineContent(
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
      final text = cleanLyricText(rawText.substring(match.end, nextStart));
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
      return ParsedLyricLineContent(text.trim(), segments);
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
      final text = cleanLyricText(rawText.substring(match.end, nextStart));
      if (text.isEmpty) {
        continue;
      }
      final start = parseLyricTimestamp(
        match.group(1),
        match.group(2),
        match.group(3),
      );
      segments.add(LyricSegment(start, start, text));
    }
    final text = segments.map((segment) => segment.text).join();
    if (text.trim().isNotEmpty) {
      return ParsedLyricLineContent(text.trim(), segments);
    }
  }

  return ParsedLyricLineContent(cleanLyricText(rawText), const []);
}

String cleanLyricText(String text) {
  return text
      .replaceAll(RegExp(r'\[[a-zA-Z]+:[^\]]*\]'), '')
      .replaceAll(RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>'), '')
      .replaceAll(RegExp(r'[\(<](\d{1,8}),(\d{1,8})[\)>]'), '')
      .trim();
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

class LyricLineTime {
  const LyricLineTime(this.startMs, this.endMs);

  final int startMs;
  final int? endMs;
}

class ParsedLyricLineContent {
  const ParsedLyricLineContent(this.text, this.segments);

  final String text;
  final List<LyricSegment> segments;
}


