import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/tag_ordering.dart';
import 'package:aetheria/features/library/ui/settings/settings_theme_tab.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/library/ui/song_table/song_tag_alignment.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_tags.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/features/player/ui/detail/song_tag_editor.dart';
import 'package:aetheria/src/rust/models/song.dart';

import 'support/ui_test_fakes.dart';

Song _songWithTags(String id, String title, List<Tag> tags) => Song(
      id: id,
      title: title,
      artist: 'Artist',
      rating: 0,
      createdAt: '',
      versions: const [],
      tags: tags,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsThemeTab toggles tag alignment mode', (tester) async {
    final theme = UIThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<UIThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          theme: theme.themeData,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsThemeTab(
                cfg: theme.currentTheme,
                themeProvider: theme,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌曲表格标签对齐模式'), findsOneWidget);
    expect(theme.tagAlignmentEnabled, isFalse);

    await tester.tap(find.text('歌曲表格标签对齐模式'));
    await tester.pumpAndSettle();

    expect(theme.tagAlignmentEnabled, isTrue);
  });

  testWidgets(
    'TagManagerModal reorders categories and tags via arrows and drag handles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const tPop = Tag(id: 1, name: '流行', category: '流派');
      const tRock = Tag(id: 2, name: '摇滚', category: '流派');
      const tZh = Tag(id: 3, name: '中文', category: '语言');
      const tMood = Tag(id: 4, name: '治愈', category: '情绪');

      final library = TestLibrary()
        ..tags = const [tPop, tRock, tZh, tMood]
        ..isLoading = false;
      addTearDown(library.dispose);
      final theme = UIThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
          ],
          child: MaterialApp(
            theme: theme.themeData,
            home: const Scaffold(body: TagManagerModal()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default category order: 流派 -> 语言 -> 情绪.
      expect(
        tester.getTopLeft(find.text('流派')).dy,
        lessThan(tester.getTopLeft(find.text('语言')).dy),
      );
      expect(
        tester.getTopLeft(find.text('语言')).dy,
        lessThan(tester.getTopLeft(find.text('情绪')).dy),
      );

      // Move 情绪 up via arrow button -> now before 语言.
      await tester.tap(find.byTooltip('上移种类 情绪'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('情绪')).dy,
        lessThan(tester.getTopLeft(find.text('语言')).dy),
      );

      // Inside 流派: default order is 摇滚 then 流行; move 摇滚 down via arrow.
      expect(
        tester.getTopLeft(find.text('摇滚')).dy,
        lessThan(tester.getTopLeft(find.text('流行')).dy),
      );
      await tester.tap(find.byTooltip('下移标签 摇滚'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('流行')).dy,
        lessThan(tester.getTopLeft(find.text('摇滚')).dy),
      );

      // Drag tag handle of 摇滚 back up above 流行.
      final rockHandle = find.descendant(
        of: find.ancestor(
          of: find.text('摇滚'),
          matching: find.byKey(const ValueKey('tag-item-2')),
        ),
        matching: find.byTooltip('拖拽调整标签优先度'),
      );
      final popTop = tester.getCenter(find.text('流行'));
      await tester.drag(
        rockHandle,
        Offset(0, popTop.dy - tester.getCenter(rockHandle).dy - 10),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('摇滚')).dy,
        lessThan(tester.getTopLeft(find.text('流行')).dy),
      );

      // Drag category handle of 流派 downward past 情绪.
      final genreCatHandle = find.descendant(
        of: find.byKey(const ValueKey('tag-cat-流派')),
        matching: find.byTooltip('拖拽调整种类优先度'),
      );
      final moodBottom = tester.getBottomLeft(
        find.byKey(const ValueKey('tag-cat-情绪')),
      );
      await tester.timedDrag(
        genreCatHandle,
        Offset(0, moodBottom.dy - tester.getCenter(genreCatHandle).dy + 30),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('情绪')).dy,
        lessThan(tester.getTopLeft(find.text('流派')).dy),
      );

      // Tapping tag row still opens editor.
      await tester.tap(find.text('摇滚'));
      await tester.pumpAndSettle();
      expect(find.text('保存修改'), findsOneWidget);
    },
  );

  testWidgets('TagManagerModal narrow layout renders priority controls safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = TestLibrary()
      ..tags = const [
        Tag(id: 1, name: '流行', category: '流派'),
        Tag(id: 2, name: '中文', category: '语言'),
      ]
      ..isLoading = false;
    addTearDown(library.dispose);
    final theme = UIThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: const Scaffold(body: TagManagerModal()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final moveLangUp = find.byTooltip('上移种类 语言');
    expect(moveLangUp, findsOneWidget);
    await tester.ensureVisible(moveLangUp);
    await tester.pumpAndSettle();
    await tester.tap(moveLangUp);
    await tester.pumpAndSettle();

    expect(library.orderedTags.map((t) => t.name), ['中文', '流行']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TagFilter and SongTagEditor follow updated tag priorities', (
    tester,
  ) async {
    const tGenre = Tag(id: 1, name: '摇滚', category: '流派');
    const tLang = Tag(id: 2, name: '中文', category: '语言');
    final song = _songWithTags('s1', 'Track 1', const [tGenre]);
    final library = TestLibrary()
      ..tags = const [tGenre, tLang]
      ..songs = [song]
      ..isLoading = false;
    addTearDown(library.dispose);
    final theme = UIThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: Scaffold(
            body: Column(
              children: [
                const TagFilter(),
                Expanded(child: SongTagEditor(song: song)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final filterChipsBefore = find.descendant(
      of: find.byType(TagFilter),
      matching: find.text('摇滚'),
    );
    final filterLangBefore = find.descendant(
      of: find.byType(TagFilter),
      matching: find.text('中文'),
    );
    expect(
      tester.getTopLeft(filterChipsBefore).dx,
      lessThan(tester.getTopLeft(filterLangBefore).dx),
    );

    await library.moveTagCategory(1, 0); // 语言 -> first
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(filterLangBefore).dx,
      lessThan(tester.getTopLeft(filterChipsBefore).dx),
    );
    final editorGenre = find.descendant(
      of: find.byType(SongTagEditor),
      matching: find.text('摇滚'),
    );
    final editorLang = find.descendant(
      of: find.byType(SongTagEditor),
      matching: find.text('中文'),
    );
    expect(
      tester.getTopLeft(editorLang).dy,
      lessThan(tester.getTopLeft(editorGenre).dy),
    );
  });

  testWidgets('SongTable aligns tag columns by category slot and updates with list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const tPop = Tag(id: 1, name: '流行', category: '流派');
    const tRock = Tag(id: 2, name: '摇滚', category: '流派');
    const tZh = Tag(id: 3, name: '中文', category: '语言');
    const tLongLang = Tag(id: 4, name: '非常长语言标签', category: '语言');
    const tHeal = Tag(id: 5, name: '治愈', category: '情绪');

    final song1 = _songWithTags('s1', 'Track 1', const [tHeal, tPop, tRock]);
    final song2 = _songWithTags('s2', 'Track 2', const [tZh, tRock]);
    final song3 = _songWithTags('s3', 'Track 3', const [tLongLang]);
    final song4 = _songWithTags('s4', 'Track 4', const []);

    final library = TestLibrary()
      ..tags = const [tPop, tRock, tZh, tLongLang, tHeal]
      ..songs = [song1, song2, song3, song4]
      ..isLoading = false;
    addTearDown(library.dispose);
    final audio = TestAudio();
    addTearDown(audio.dispose);
    final theme = UIThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ChangeNotifierProvider<AudioPlayerProvider>.value(value: audio),
          ChangeNotifierProvider<UIThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.themeData,
          home: const Scaffold(body: SongTable()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unaligned mode: song4 renders em-dash and song2's 中文 sits directly in
    // slot 1 (matching song1's second tag 流行), NOT pushed past genre slot 1.
    expect(find.text('—'), findsOneWidget);
    final unalignedPopSong1 = tester.getTopLeft(find.text('流行')).dx;
    final unalignedZhSong2 = tester.getTopLeft(find.text('中文')).dx;
    expect(unalignedZhSong2, closeTo(unalignedPopSong1, 1.0));

    // Enable alignment mode.
    await theme.setTagAlignmentEnabled(true);
    await tester.pumpAndSettle();

    // Empty-tag rows keep blank aligned cells instead of showing '—'.
    expect(find.text('—'), findsNothing);

    // Language slot 0 (中文 in song2 and 非常长语言标签 in song3) shares the exact X.
    final langXSong2 = tester.getTopLeft(find.text('中文')).dx;
    final langXSong3 = tester.getTopLeft(find.text('非常长语言标签')).dx;
    expect(langXSong2, closeTo(langXSong3, 0.01));

    // Genre slot 0 (摇滚 in both song1 and song2) aligns at column start.
    final genreSlot0Song1 = tester.getTopLeft(find.text('摇滚').first).dx;
    final genreSlot0Song2 = tester.getTopLeft(find.text('摇滚').at(1)).dx;
    expect(genreSlot0Song1, closeTo(genreSlot0Song2, 0.01));

    // Language slot 0 sits past both genre slots (after song1's second genre chip).
    final genreSlot1Song1Right = tester.getTopRight(find.text('流行')).dx;
    expect(langXSong2, greaterThan(genreSlot1Song1Right));

    // Emotion slot 0 (治愈 in song1) clears the widest language tag (非常长语言标签).
    final healX = tester.getTopLeft(find.text('治愈')).dx;
    final longLangRight = tester.getTopRight(find.text('非常长语言标签')).dx;
    expect(healX, greaterThan(longLangRight));

    // Filter out Track 3 so 非常长语言标签 leaves current list; columns tighten.
    library.setSearchQuery('Track 1');
    await tester.pumpAndSettle();
    final narrowedHealX = tester.getTopLeft(find.text('治愈')).dx;
    expect(narrowedHealX, lessThan(healX));
  });

  testWidgets('SongTableTags aligned mode avoids nested scrollable when fitting', (
    tester,
  ) async {
    const tA = Tag(id: 1, name: '摇滚', category: '流派');
    const tB = Tag(id: 2, name: '中文', category: '语言');
    final plan = SongTagAlignmentPlan.fromSongs(
      [
        _songWithTags('1', 'A', const [tA, tB]),
      ],
      orderConfig: const TagOrderConfig(),
      measureChipWidth: (_) => 50,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Center(
          child: SizedBox(
            width: 240,
            height: 52,
            child: SongTableTags(
              tags: const [tA, tB],
              cfg: AppThemeConfig.dark,
              availableWidth: 240,
              alignmentPlan: plan,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);

    // Narrow availableWidth triggers horizontal scroll cleanly.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Center(
          child: SizedBox(
            width: 80,
            height: 52,
            child: SongTableTags(
              tags: const [tA, tB],
              cfg: AppThemeConfig.dark,
              availableWidth: 80,
              alignmentPlan: plan,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Scrollable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
