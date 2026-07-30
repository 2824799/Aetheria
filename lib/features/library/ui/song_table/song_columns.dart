/// Desktop song table column model + width defaults.
library;

enum SongColumnKey { title, artist, tags, versions, spec }

extension SongColumnKeyX on SongColumnKey {
  String get label => switch (this) {
        SongColumnKey.title => '歌曲名称',
        SongColumnKey.artist => '歌手',
        SongColumnKey.tags => '标签',
        SongColumnKey.versions => '版本数',
        SongColumnKey.spec => '默认音质',
      };

  double get defaultWidth => switch (this) {
        SongColumnKey.title => 280,
        SongColumnKey.artist => 200,
        SongColumnKey.tags => 240,
        SongColumnKey.versions => 92,
        SongColumnKey.spec => 170,
      };

  double get minWidth => switch (this) {
        SongColumnKey.title => 180,
        SongColumnKey.artist => 140,
        SongColumnKey.tags => 160,
        SongColumnKey.versions => 92,
        SongColumnKey.spec => 140,
      };
}
