import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_tags.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('fitting tags avoid nested scrolling (text scale $scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tags(220, scale, const [
          Tag(id: 1, name: '日语'),
          Tag(id: 2, name: '收藏'),
        ]),
      );
      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('overflow tags remain scrollable (text scale $scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tags(100, scale, const [
          Tag(id: 1, name: '很长的歌曲分类标签'),
          Tag(id: 2, name: '另一个标签'),
        ]),
      );
      final scroll = find.byType(Scrollable);
      expect(scroll, findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _tags(double width, double scale, List<Tag> tags) => MaterialApp(
  theme: buildAetheriaThemeData(AppThemeConfig.dark),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Center(
      child: SizedBox(
        width: width,
        height: 52,
        child: SongTableTags(
          tags: tags,
          cfg: AppThemeConfig.dark,
          availableWidth: width,
        ),
      ),
    ),
  ),
);
