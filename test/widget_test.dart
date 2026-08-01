import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/settings/settings_theme_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('theme settings expose the dark pink option', (tester) async {
    final provider = UIThemeProvider();
    await tester.pumpWidget(
      MaterialApp(
        theme: provider.themeData,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: SettingsThemeTab(
              cfg: provider.currentTheme,
              themeProvider: provider,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暮樱暗粉'), findsOneWidget);
  });
}
