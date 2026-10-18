import 'dart:ui' as ui;

import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('idle prefetch pauses for scrolling and reuses bounded layouts', (
    tester,
  ) async {
    final cache = SongTableTextCache(capacity: 90);
    addTearDown(cache.dispose);
    final titles = List.generate(20, (i) => '歌曲 $i');
    cache.configurePrefetch(
      revision: titles,
      titles: titles,
      artists: const [],
    );
    Widget sample(String label) => MaterialApp(
      home: SizedBox(
        width: 160,
        height: 52,
        child: Center(
          child: SongTableText(
            label,
            cache: cache,
            prefetchGroup: SongTableTextGroup.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    await tester.pumpWidget(sample(titles.first));
    cache.configurePrefetch(
      revision: List.of(titles),
      titles: titles,
      artists: const [],
    );
    cache.deferWarmup();
    await tester.pump(const Duration(milliseconds: 50));
    expect(cache.idleLayouts, 0);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 220)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(cache.idleLayouts, greaterThanOrEqualTo(19));
    final misses = cache.layoutMisses;
    await tester.pumpWidget(sample(titles.last));
    expect(cache.layoutMisses, misses);
    expect(cache.cachedLayouts, lessThanOrEqualTo(cache.capacity));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
  for (final direction in TextDirection.values) {
    for (final overflow in [TextOverflow.clip, TextOverflow.ellipsis]) {
      testWidgets('cached label matches Text pixels: $direction $overflow', (
        tester,
      ) async {
        final cache = SongTableTextCache(capacity: 2);
        addTearDown(cache.dispose);
        final original = GlobalKey();
        final cached = GlobalKey();
        const label = '歌曲 · いったりきたり · Artist 123';
        const style = TextStyle(
          fontSize: 15,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        );
        Widget sample(GlobalKey key, Widget child) => RepaintBoundary(
          key: key,
          child: SizedBox(width: 160, height: 52, child: Center(child: child)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
                child: Column(
                  children: [
                    sample(
                      original,
                      Text(
                        label,
                        style: style,
                        maxLines: 1,
                        overflow: overflow,
                      ),
                    ),
                    sample(
                      cached,
                      SongTableText(
                        label,
                        cache: cache,
                        style: style,
                        maxLines: 1,
                        overflow: overflow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<List<int>> pixels(GlobalKey key) async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          return (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
            } finally {
              image.dispose();
            }
          }))!;
        }

        expect(await pixels(cached), await pixels(original));
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel(label), findsNWidgets(2));
        semantics.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'eviction and font changes preserve mounted labels; width/style relayout',
    (tester) async {
      final cache = SongTableTextCache(capacity: 1);
      addTearDown(cache.dispose);
      for (final width in [200.0, 80.0, 160.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    for (var i = 0; i < 5; i++)
                      SongTableText(
                        'Text $i at $width',
                        cache: cache,
                        style: TextStyle(fontSize: width / 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.binding.handleSystemMessage({'type': 'fontsChange'});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
