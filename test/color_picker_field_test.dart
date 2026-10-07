import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/color_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('color parsing preserves alpha and rejects incomplete input', () {
    expect(parsePickerColor('#804488CC'), const Color(0x804488cc));
    expect(parsePickerColor(' #4488cc '), const Color(0xff4488cc));
    expect(parsePickerColor('#oops'), isNull);
    expect(parsePickerColor('#123'), isNull);
    expect(
      pickerColorHex(const Color(0x00123456), includeAlpha: true),
      '#00123456',
    );
  });

  test('live lyric color preview never writes preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = FloatingLyricsProvider();
    await provider.load();
    provider.previewColors(played: const Color(0x8088ff44));
    expect(provider.playedColor, const Color(0x8088ff44));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('aetheria-floating-lyrics-played-color'), isNull);
    await provider.setPlayedColor(provider.playedColor);
    expect(prefs.getInt('aetheria-floating-lyrics-played-color'), 0x8088ff44);
    provider.dispose();
  });

  testWidgets('HSV/hex preview, validation, cancel and alpha confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = UIThemeProvider();
    final commits = <String>[];
    final previews = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.themeData,
        home: Scaffold(
          body: ColorPickerField(
            cfg: theme.currentTheme,
            value: '#804488CC',
            enableAlpha: true,
            showPresets: false,
            livePreview: true,
            onChanged: commits.add,
            onPreview: previews.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('自定义 #804488CC'));
    await tester.pumpAndSettle();
    expect(find.text('不透明度'), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('color-sv-plane'))),
    );
    await tester.pump();
    expect(previews, isNotEmpty);
    expect(commits, isEmpty);
    final input = find.descendant(
      of: find.byKey(const ValueKey('color-hex')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '#80F02010');
    await tester.pump();
    expect(previews.last, '#80F02010');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(previews.last, '#804488CC');
    expect(commits, isEmpty);

    await tester.tap(find.text('自定义 #804488CC'));
    await tester.pumpAndSettle();
    await tester.enterText(input, '#bad');
    await tester.pump();
    expect(find.text('请输入 #RRGGBB 或 #AARRGGBB'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    await tester.enterText(input, '#20AABBCC');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(commits, ['#20AABBCC']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    theme.dispose();
  });
}
