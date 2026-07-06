import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';

class LoadedLyricContent {
  const LoadedLyricContent({
    required this.content,
    this.translation,
    this.romanized,
  });

  final String content;
  final String? translation;
  final String? romanized;
}

class LyricSearchCandidate {
  const LyricSearchCandidate({
    required this.source,
    required this.sourceLabel,
    required this.title,
    this.artist,
    this.album,
    this.sourceId,
    this.durationSec,
    this.content,
    this.translation,
    this.romanized,
    this.payload = const <String, Object?>{},
  });

  final String source;
  final String sourceLabel;
  final String? sourceId;
  final String title;
  final String? artist;
  final String? album;
  final int? durationSec;
  final String? content;
  final String? translation;
  final String? romanized;
  final Map<String, Object?> payload;

  bool get hasInlineContent => content != null && content!.trim().isNotEmpty;
}

class LyricSearchService {
  const LyricSearchService._();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  static Future<List<LyricSearchCandidate>> search(
    Song song,
    AudioVersion? version,
  ) async {
    final tasks = <Future<List<LyricSearchCandidate>>>[
      _guard(_searchLocal(song, version)),
      _guard(_searchNetease(song, version)),
      _guard(_searchQq(song, version)),
      _guard(_searchKugou(song, version)),
      _guard(_searchLrclib(song, version)),
    ];

    final groups = await Future.wait(tasks);
    final results = <LyricSearchCandidate>[];
    final seen = <String>{};
    for (final group in groups) {
      for (final candidate in group) {
        final key = [
          candidate.source,
          candidate.sourceId ?? '',
          candidate.title,
          candidate.artist ?? '',
          candidate.content?.hashCode.toString() ?? '',
        ].join('|');
        if (seen.add(key)) {
          results.add(candidate);
        }
      }
    }
    return results;
  }

  static Future<LoadedLyricContent> loadCandidate(
    LyricSearchCandidate candidate,
  ) async {
    if (candidate.hasInlineContent) {
      return LoadedLyricContent(
        content: candidate.content!.trim(),
        translation: _emptyToNull(candidate.translation),
        romanized: _emptyToNull(candidate.romanized),
      );
    }

    switch (candidate.source) {
      case 'netease':
        return _loadNetease(candidate);
      case 'qq':
        return _loadQq(candidate);
      case 'kugou':
        return _loadKugou(candidate);
      default:
        throw Exception('这个歌词来源暂时不能预览。');
    }
  }

  static Future<List<LyricSearchCandidate>> _guard(
    Future<List<LyricSearchCandidate>> task,
  ) async {
    try {
      return await task;
    } catch (_) {
      return const <LyricSearchCandidate>[];
    }
  }

  static Future<List<LyricSearchCandidate>> _searchLocal(
    Song song,
    AudioVersion? version,
  ) async {
    final locals = await music.getLocalLyricCandidates(
      songId: song.id,
      audioVersionId: version?.id,
    );
    return locals
        .map(
          (item) => LyricSearchCandidate(
            source: item.source,
            sourceLabel: _localSourceLabel(item.source),
            sourceId: item.sourceId,
            title: item.title,
            artist: item.artist,
            content: item.content,
          ),
        )
        .toList(growable: false);
  }

  static Future<List<LyricSearchCandidate>> _searchLrclib(
    Song song,
    AudioVersion? version,
  ) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': song.title,
      if ((song.artist ?? '').trim().isNotEmpty) 'artist_name': song.artist!,
      if ((song.album ?? '').trim().isNotEmpty) 'album_name': song.album!,
    });
    final json = await _getJson(uri);
    if (json is! List) {
      return const <LyricSearchCandidate>[];
    }
    return json
        .take(12)
        .map((raw) {
          final item = raw as Map;
          final synced = _asString(item['syncedLyrics']);
          final plain = _asString(item['plainLyrics']);
          return LyricSearchCandidate(
            source: 'lrclib',
            sourceLabel: 'LRCLIB',
            sourceId: _asString(item['id']),
            title: _asString(item['trackName']) ?? song.title,
            artist: _asString(item['artistName']) ?? song.artist,
            album: _asString(item['albumName']),
            durationSec: _asInt(item['duration']) ?? version?.duration.round(),
            content: _emptyToNull(synced) ?? _emptyToNull(plain),
          );
        })
        .where((item) => item.content != null)
        .toList(growable: false);
  }

  static Future<List<LyricSearchCandidate>> _searchNetease(
    Song song,
    AudioVersion? version,
  ) async {
    final query = _query(song);
    final uri = Uri.https('music.163.com', '/api/search/get/web', {
      'csrf_token': '',
      's': query,
      'type': '1',
      'offset': '0',
      'total': 'true',
      'limit': '10',
    });
    final json = await _getJson(uri, headers: _neteaseHeaders);
    final songs = _at(json, const ['result', 'songs']) as List?;
    if (songs == null) {
      return const <LyricSearchCandidate>[];
    }
    return songs
        .map((raw) {
          final item = raw as Map;
          final artists = (item['artists'] as List?)
              ?.map((artist) => _asString((artist as Map)['name']))
              .whereType<String>()
              .join(' / ');
          return LyricSearchCandidate(
            source: 'netease',
            sourceLabel: '网易云音乐',
            sourceId: _asString(item['id']),
            title: _asString(item['name']) ?? song.title,
            artist: _emptyToNull(artists) ?? song.artist,
            album: _asString(_at(item, const ['album', 'name'])),
            durationSec: (_asInt(item['duration']) ?? 0) > 0
                ? (_asInt(item['duration'])! / 1000).round()
                : version?.duration.round(),
          );
        })
        .where((item) => item.sourceId != null)
        .toList(growable: false);
  }

  static Future<LoadedLyricContent> _loadNetease(
    LyricSearchCandidate candidate,
  ) async {
    final id = candidate.sourceId;
    if (id == null) {
      throw Exception('缺少网易歌词 ID。');
    }
    final uri = Uri.https('music.163.com', '/api/song/lyric', {
      'id': id,
      'lv': '1',
      'kv': '1',
      'tv': '-1',
    });
    final json = await _getJson(uri, headers: _neteaseHeaders);
    final content = _asString(_at(json, const ['lrc', 'lyric']));
    if (_emptyToNull(content) == null) {
      throw Exception('这个网易候选没有可用歌词。');
    }
    return LoadedLyricContent(
      content: content!.trim(),
      translation: _emptyToNull(
        _asString(_at(json, const ['tlyric', 'lyric'])),
      ),
      romanized: _emptyToNull(_asString(_at(json, const ['romalrc', 'lyric']))),
    );
  }

  static Future<List<LyricSearchCandidate>> _searchQq(
    Song song,
    AudioVersion? version,
  ) async {
    final uri = Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {
      'format': 'json',
      'p': '1',
      'n': '10',
      'w': _query(song),
      'cr': '1',
      'g_tk': '5381',
      't': '0',
      'inCharset': 'utf8',
      'outCharset': 'utf-8',
    });
    final json = await _getJson(uri, headers: _qqHeaders);
    final list = _at(json, const ['data', 'song', 'list']) as List?;
    if (list == null) {
      return const <LyricSearchCandidate>[];
    }
    return list
        .map((raw) {
          final item = raw as Map;
          final singers = (item['singer'] as List?)
              ?.map((singer) => _asString((singer as Map)['name']))
              .whereType<String>()
              .join(' / ');
          final mid = _asString(item['songmid']);
          return LyricSearchCandidate(
            source: 'qq',
            sourceLabel: 'QQ音乐',
            sourceId: mid,
            title: _asString(item['songname']) ?? song.title,
            artist: _emptyToNull(singers) ?? song.artist,
            album: _asString(item['albumname']),
            durationSec: _asInt(item['interval']) ?? version?.duration.round(),
          );
        })
        .where((item) => item.sourceId != null)
        .toList(growable: false);
  }

  static Future<LoadedLyricContent> _loadQq(
    LyricSearchCandidate candidate,
  ) async {
    final mid = candidate.sourceId;
    if (mid == null) {
      throw Exception('缺少 QQ 音乐歌词 ID。');
    }
    final uri =
        Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
          'songmid': mid,
          'format': 'json',
          'nobase64': '1',
          'g_tk': '5381',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
        });
    final json = await _getJson(uri, headers: _qqHeaders);
    final rawLyric = _asString(json is Map ? json['lyric'] : null);
    final content = _decodeMaybeBase64(_htmlUnescape(rawLyric ?? ''));
    if (_emptyToNull(content) == null) {
      throw Exception('这个 QQ 音乐候选没有可用歌词。');
    }
    final trans = _decodeMaybeBase64(
      _htmlUnescape(_asString(json is Map ? json['trans'] : null) ?? ''),
    );
    return LoadedLyricContent(
      content: content.trim(),
      translation: _emptyToNull(trans),
    );
  }

  static Future<List<LyricSearchCandidate>> _searchKugou(
    Song song,
    AudioVersion? version,
  ) async {
    final uri = Uri.https('mobilecdn.kugou.com', '/api/v3/search/song', {
      'format': 'json',
      'keyword': _query(song),
      'page': '1',
      'pagesize': '10',
      'showtype': '1',
    });
    final json = await _getJson(uri);
    final list = _at(json, const ['data', 'info']) as List?;
    if (list == null) {
      return const <LyricSearchCandidate>[];
    }
    return list
        .map((raw) {
          final item = raw as Map;
          final duration =
              _asInt(item['duration']) ?? version?.duration.round();
          return LyricSearchCandidate(
            source: 'kugou',
            sourceLabel: '酷狗音乐',
            sourceId: _asString(item['hash']),
            title: _asString(item['songname']) ?? song.title,
            artist: _asString(item['singername']) ?? song.artist,
            album: _asString(item['album_name']),
            durationSec: duration,
            payload: <String, Object?>{
              'keyword': _query(song),
              'durationMs': duration == null ? null : duration * 1000,
            },
          );
        })
        .where((item) => item.sourceId != null)
        .toList(growable: false);
  }

  static Future<LoadedLyricContent> _loadKugou(
    LyricSearchCandidate candidate,
  ) async {
    final hash = candidate.sourceId;
    if (hash == null) {
      throw Exception('缺少酷狗歌词 Hash。');
    }
    final searchUri = Uri.http('lyrics.kugou.com', '/search', {
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      'keyword':
          _asString(candidate.payload['keyword']) ??
          '${candidate.artist ?? ''} ${candidate.title}'.trim(),
      'duration': (_asInt(candidate.payload['durationMs']) ?? 0).toString(),
      'hash': hash,
    });
    final searchJson = await _getJson(searchUri);
    final candidates =
        (searchJson is Map ? searchJson['candidates'] : null) as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('酷狗没有返回可用歌词。');
    }
    final first = candidates.first as Map;
    final id = _asString(first['id']);
    final accessKey = _asString(first['accesskey']);
    if (id == null || accessKey == null) {
      throw Exception('酷狗歌词下载信息不完整。');
    }
    final downloadUri = Uri.http('lyrics.kugou.com', '/download', {
      'ver': '1',
      'client': 'pc',
      'id': id,
      'accesskey': accessKey,
      'fmt': 'lrc',
      'charset': 'utf8',
    });
    final downloadJson = await _getJson(downloadUri);
    final encoded = _asString(
      downloadJson is Map ? downloadJson['content'] : null,
    );
    if (encoded == null) {
      throw Exception('酷狗歌词内容为空。');
    }
    final content = utf8.decode(base64Decode(encoded));
    if (_emptyToNull(content) == null) {
      throw Exception('酷狗歌词内容为空。');
    }
    return LoadedLyricContent(content: content.trim());
  }

  static Future<dynamic> _getJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static String _query(Song song) {
    final artist = (song.artist ?? '').trim();
    return artist.isEmpty ? song.title.trim() : '$artist ${song.title}'.trim();
  }

  static String _localSourceLabel(String source) {
    return switch (source) {
      'local_embedded' => '音频内嵌',
      'local_lrc' => '本地 LRC',
      'legacy_song' => '旧版歌曲歌词',
      _ => '本地歌词',
    };
  }

  static Map<String, String> get _neteaseHeaders => const {
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
  };

  static Map<String, String> get _qqHeaders => const {
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
  };

  static String? _asString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  static Object? _at(Object? value, List<String> path) {
    Object? current = value;
    for (final key in path) {
      if (current is! Map) {
        return null;
      }
      current = current[key];
    }
    return current;
  }

  static int? _asInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value.toString());
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _decodeMaybeBase64(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains('[')) {
      return trimmed;
    }
    try {
      return utf8.decode(base64Decode(trimmed));
    } catch (_) {
      return trimmed;
    }
  }

  static String _htmlUnescape(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}
