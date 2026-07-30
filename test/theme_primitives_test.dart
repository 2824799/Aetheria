import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/widgets.dart';

void main() {
  test('theme configs expose legacy and semantic colors', () {
    final dark = AppThemeConfig.dark;
    expect(dark.textMain, dark.textPrimary);
    expect(dark.textSub, dark.textSecondary);
    expect(dark.border, dark.borderSubtle);
    expect(dark.danger, isNot(dark.accent));
    expect(dark.success, isNot(dark.warning));
    expect(dark.scrim.a, greaterThan(0));
  });

  test('motion exit is faster than enter', () {
    final exit = AetherMotion.exit(AetherMotion.panel);
    expect(exit.inMilliseconds, lessThan(AetherMotion.panel.inMilliseconds));
  });

  test('lyric palettes and fallbacks are non-empty', () {
    expect(AetherLyricPalettes.unplayed, isNotEmpty);
    expect(AetherLyricPalettes.played, isNotEmpty);
    expect(AetherLyricPalettes.shadow, isNotEmpty);
    expect(AetherFallbackColors.accent.a, greaterThan(0));
  });

  test('play bar height token matches desktop control row', () {
    expect(AetherSpace.playBarHeight, 90);
  });

  testWidgets('ThemeExtension is available via context.tokens', (tester) async {
    late AppThemeConfig seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Builder(
          builder: (context) {
            seen = context.tokens;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen.accent, AppThemeConfig.dark.accent);
  });

  testWidgets('AetherButton primary renders label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.pink),
        home: Scaffold(
          body: AetherButton.primary(
            label: '导入歌曲',
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('导入歌曲'), findsOneWidget);
  });

  testWidgets('AetherDialog shows title and actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.light),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AetherButton(
                label: 'Open',
                onPressed: () {
                  showAetherDialog<void>(
                    context: context,
                    builder: (ctx) => AetherDialog(
                      title: '确认删除',
                      content: const Text('msg'),
                      actions: [
                        AetherButton.ghost(
                          label: '取消',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('showAetherConfirmDialog returns false on cancel', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AetherButton.primary(
                label: 'Ask',
                onPressed: () async {
                  result = await showAetherConfirmDialog(
                    context: context,
                    title: '删除？',
                    message: '不可撤销',
                    dangerous: true,
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('删除？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('AetherTabBar switches active tab', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AetherTabBar(
                value: value,
                onChanged: (id) => setState(() => value = id),
                tabs: const [
                  AetherTabItem(id: 'a', label: '滚动歌词'),
                  AetherTabItem(id: 'b', label: '歌词管理'),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('滚动歌词'), findsOneWidget);
    await tester.tap(find.text('歌词管理'));
    await tester.pumpAndSettle();
    expect(find.text('歌词管理'), findsOneWidget);
  });

  testWidgets('AetherTextField.plain renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.light),
        home: const Scaffold(
          body: AetherTextField.plain(hintText: '标题'),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('showAetherToast inserts overlay content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AetherButton.primary(
                label: 'Toast',
                onPressed: () {
                  showAetherToast(
                    context,
                    message: '已保存',
                    kind: AetherToastKind.success,
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Toast'));
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('AetherCheckbox toggles via onChanged', (tester) async {
    bool? value = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAetheriaThemeData(AppThemeConfig.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AetherCheckbox(
                value: value ?? false,
                onChanged: (v) => setState(() => value = v),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });
}

