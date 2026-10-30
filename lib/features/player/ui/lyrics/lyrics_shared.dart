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

String sanitizeLyricContent(String content) {
  final cleanLines = <String>[];
  for (final rawLine in content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('[awlrc:') ||
        lower.startsWith('[kana:') ||
        lower.startsWith('[encoding:') ||
        lower.startsWith('[re:') ||
        lower.startsWith('[ve:') ||
        lower.startsWith('[offset:')) {
      continue;
    }
    if (trimmed.length > 500 && !trimmed.contains(' ')) {
      continue;
    }
    cleanLines.add(trimmed);
  }
  return cleanLines.join('\n');
}

const lyricsFontFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'sans-serif',
];
