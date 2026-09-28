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
