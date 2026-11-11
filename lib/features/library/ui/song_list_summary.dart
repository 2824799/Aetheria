import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';

/// Name of the list on screen: the active playlist, or the whole library.
String songListTitle(LibraryProvider library) {
  final playlistId = library.activePlaylistId;
  for (final playlist in library.playlists) {
    if (playlist.id == playlistId) return playlist.name;
  }
  return '全部歌曲';
}

/// How many songs the list shows, and out of how many when it is filtered.
String songListCount(LibraryProvider library) {
  final total = library.activePlaylistId == null
      ? library.songs.length
      : library.playlistSongIds.length;
  final shown = library.displaySongs.length;
  return shown == total ? '$total 首' : '$shown / $total 首';
}

/// Explains why the song list is empty: nothing imported yet, an empty
/// playlist, or a search/tag filter that matches nothing.
class SongListEmptyState extends StatelessWidget {
  const SongListEmptyState({
    super.key,
    required this.library,
    this.touch = false,
  });

  final LibraryProvider library;

  /// Word the hints for the touch layout instead of the desktop one.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    if (library.songs.isEmpty) {
      return AetherEmptyState(
        icon: Icons.library_music_outlined,
        title: '音乐库还是空的',
        message: touch
            ? '在“设置 › 音乐库”中导入本地音频'
            : '点击右上角的“导入歌曲”添加本地音频',
      );
    }
    final filtered =
        library.searchQuery.isNotEmpty ||
        library.selectedTags.isNotEmpty ||
        library.excludedTags.isNotEmpty;
    if (library.activePlaylistId != null && !filtered) {
      return AetherEmptyState(
        icon: Icons.queue_music_rounded,
        title: '歌单里还没有歌曲',
        message: touch
            ? '在“全部歌曲”中长按歌曲，可以把它添加到歌单'
            : '在“全部歌曲”中右键歌曲，可以把它添加到歌单',
      );
    }
    return const AetherEmptyState(
      icon: Icons.search_off_rounded,
      title: '没有符合条件的歌曲',
      message: '试试调整搜索词或标签筛选',
    );
  }
}
