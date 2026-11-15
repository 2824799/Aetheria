import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/tag_ordering.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';

class _FakeTagLibraryApi extends Fake implements RustLibApi {
  List<Tag> dbTags = const [];
  List<Song> dbSongs = const [];

  @override
  bool crateApiMusicIsLibraryInitialized() => true;

  @override
  Future<List<Song>> crateApiMusicGetSongs() async => dbSongs;

  @override
  Future<List<Tag>> crateApiMusicGetTags() async => dbTags;

  @override
  Future<List<Playlist>> crateApiMusicGetPlaylists() async => const [];

  @override
  Future<String> crateApiMusicGetLibraryPath() async => '/tmp/aetheria_tags';

  @override
  Future<List<String>> crateApiMusicGetSongIdsWithLyrics() async => const [];

  @override
  Future<void> crateApiMusicUpdateTag({
    required Object tagId,
    required String name,
    String? color,
    String? category,
  }) async {}

  @override
  Future<void> crateApiMusicDeleteTag({required Object tagId}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TagOrderConfig', () {
    const sampleTags = [
      Tag(id: 1, name: '摇滚', category: '流派'),
      Tag(id: 2, name: '流行', category: '流派'),
      Tag(id: 3, name: '中文', category: '语言'),
      Tag(id: 4, name: '日韩', category: '语言'),
      Tag(id: 5, name: '治愈', category: '情绪'),
      Tag(id: 6, name: '夜间', category: '自定义'),
    ];

    test('sorts categories by default tiers then custom then 自定义', () {
      const mixed = [
        Tag(id: 10, name: 'A', category: null),
        Tag(id: 11, name: 'B', category: '自建类'),
        Tag(id: 12, name: 'C', category: '情绪'),
        Tag(id: 13, name: 'D', category: '流派'),
      ];
      const config = TagOrderConfig();
      final sorted = config.sortTags(mixed);
      expect(
        sorted.map((t) => effectiveTagCategory(t)),
        ['流派', '情绪', '自建类', '自定义'],
      );
    });

    test('sorts first by category order then by tag order in category', () {
      const config = TagOrderConfig(
        categoryOrder: ['语言', '情绪', '流派'],
        tagOrderByCategory: {
          '语言': [4, 3],
          '流派': [1, 2],
        },
      );
      final sorted = config.sortTags(sampleTags);
      expect(sorted.map((t) => t.id), [4, 3, 5, 1, 2, 6]);
      // Re-sorting an already-sorted list returns the same instance.
      expect(identical(config.sortTags(sorted), sorted), isTrue);
    });

    test('moves categories and in-category tags up and down cleanly', () {
      var config = const TagOrderConfig();
      config = config.moveCategory(sampleTags, 1, 0); // 语言 above 流派
      expect(config.orderedCategoriesFrom(sampleTags), [
        '语言',
        '流派',
        '情绪',
        '自定义',
      ]);

      config = config.moveCategory(sampleTags, 0, 2); // 语言 after 情绪
      expect(config.orderedCategoriesFrom(sampleTags), [
        '流派',
        '情绪',
        '语言',
        '自定义',
      ]);

      // Default alphabetical order inside 语言 before reorder: 日韩(4), 中文(3)
      // Wait: compareTags uses lowercase name: '日韩' vs '中文'
      final langBefore = [
        for (final t in config.sortTags(sampleTags))
          if (effectiveTagCategory(t) == '语言') t.id,
      ];
      expect(langBefore, hasLength(2));
      config = config.moveTagInCategory(sampleTags, '语言', 1, 0);
      final langAfter = [
        for (final t in config.sortTags(sampleTags))
          if (effectiveTagCategory(t) == '语言') t.id,
      ];
      expect(langAfter, [langBefore[1], langBefore[0]]);
    });

    test('serializes and parses defensively via JSON', () {
      const original = TagOrderConfig(
        categoryOrder: ['情绪', '语言'],
        tagOrderByCategory: {
          '情绪': [5],
          '语言': [4, 3],
        },
      );
      final restored = TagOrderConfig.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.categoryOrder, original.categoryOrder);
      expect(restored.tagOrderByCategory, original.tagOrderByCategory);
      expect(TagOrderConfig.fromJson('bad').categoryOrder, isEmpty);
    });
  });

  group('LibraryProvider tag priority persistence & sync', () {
    final api = _FakeTagLibraryApi();

    setUpAll(() => RustLib.initMock(api: api));
    tearDownAll(RustLib.dispose);

    test('persists category & tag priorities and sorts displaySongs tags', () async {
      const tLang = Tag(id: 1, name: '中文', category: '语言');
      const tGenreA = Tag(id: 2, name: '摇滚', category: '流派');
      const tGenreB = Tag(id: 3, name: '流行', category: '流派');
      api.dbTags = const [tLang, tGenreA, tGenreB];
      api.dbSongs = const [
        Song(
          id: 's1',
          title: 'Song 1',
          rating: 0,
          createdAt: '',
          versions: [],
          tags: [tGenreB, tLang, tGenreA],
        ),
      ];

      final first = LibraryProvider();
      addTearDown(first.dispose);
      await first.loadLibrary();

      // Default: 流派 before 语言; move 语言 (index 1) above 流派 (index 0).
      await first.moveTagCategory(1, 0);
      // Inside 流派: default order is 摇滚(2) before 流行(3); move 流行(3) first.
      await first.moveTagInCategory('流派', 1, 0);

      expect(first.orderedTags.map((t) => t.id), [1, 3, 2]);
      expect(first.displaySongs.single.tags.map((t) => t.id), [1, 3, 2]);

      // Reload into a fresh provider instance from SharedPreferences.
      final second = LibraryProvider();
      addTearDown(second.dispose);
      await second.loadLibrary();

      expect(second.orderedTags.map((t) => t.id), [1, 3, 2]);
      expect(second.displaySongs.single.tags.map((t) => t.id), [1, 3, 2]);
    });

    test('exports and applies synced tagOrder payload across libraries', () async {
      final sourceLibrary = LibraryProvider()
        ..tags = const [
          Tag(id: 1, name: '中文', category: '语言'),
          Tag(id: 2, name: '摇滚', category: '流派'),
        ];
      addTearDown(sourceLibrary.dispose);
      await sourceLibrary.moveTagCategory(1, 0);

      final payload = jsonDecode(
        jsonEncode(sourceLibrary.exportTagOrderPayload()),
      );

      final targetLibrary = LibraryProvider()
        ..tags = const [
          Tag(id: 1, name: '中文', category: '语言'),
          Tag(id: 2, name: '摇滚', category: '流派'),
        ];
      addTearDown(targetLibrary.dispose);
      await targetLibrary.applySyncedTagOrder(payload);

      expect(targetLibrary.orderedTags.map((t) => t.id), [1, 2]);
    });
  });

  group('UIThemeProvider tagAlignmentEnabled', () {
    test('defaults to false and persists changes', () async {
      final theme = UIThemeProvider();
      addTearDown(theme.dispose);
      expect(theme.tagAlignmentEnabled, isFalse);

      await theme.setTagAlignmentEnabled(true);
      expect(theme.tagAlignmentEnabled, isTrue);

      final reloaded = UIThemeProvider();
      addTearDown(reloaded.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.tagAlignmentEnabled, isTrue);
    });
  });
}
