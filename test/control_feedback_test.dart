import 'package:aetheria/core/widgets/widgets.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controls = <String, Widget Function(VoidCallback)>{
    'button': (tap) => AetherButton(label: 'Button', onPressed: tap),
    'icon': (tap) => AetherIconButton(icon: Icons.play_arrow, onPressed: tap),
    'chip': (tap) => AetherChip(label: 'Chip', onTap: tap),
    'list': (tap) => AetherListTile(title: 'Row', onTap: tap),
    'switch': (tap) => AetherSwitch(value: false, onChanged: (_) => tap()),
    'choice': (tap) => AetherChoiceGroup<int>(
      value: 0,
      options: const [AetherChoiceOption(value: 1, label: 'Choice')],
      onChanged: (_) => tap(),
    ),
    'tab': (tap) => AetherTabBar(
      value: 'a',
      tabs: const [AetherTabItem(id: 'b', label: 'Tab')],
      onChanged: (_) => tap(),
    ),
  };
  for (final entry in controls.entries) {
    testWidgets(
      '${entry.key} gives visible feedback without delaying activation',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          _app(
            Center(
              child: SizedBox(width: 260, child: entry.value(() => calls++)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pressable = find.byType(AetherPressable).first;
        final gesture = await tester.startGesture(
          tester.getCenter(pressable),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        expect(calls, 1, reason: 'Activation must not wait for an animation');
        await tester.pump();
        final scale = find.descendant(
          of: pressable,
          matching: find.byType(AnimatedScale),
        );
        expect(tester.widget<AnimatedScale>(scale).scale, lessThan(1));
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedScale>(scale).scale, 1);
        expect(calls, 1);
      },
    );
  }

  testWidgets('button animation does not repaint unrelated content', (
    tester,
  ) async {
    var paints = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            AetherButton(label: 'Animate', onPressed: () {}),
            CustomPaint(
              size: const Size(200, 200),
              painter: _PaintCounter(() => paints++),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = paints;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Animate')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      paints,
      before,
      reason: 'A button must not repaint the whole screen',
    );
  });

  testWidgets(
    'nested switch acts once; disabled buttons and canceled drags do not activate',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              AetherSwitchTile(
                title: 'Switch row',
                value: false,
                onChanged: (_) => calls++,
              ),
              AetherButton(label: 'Disabled', onPressed: null),
              AetherButton(label: 'Cancel', onPressed: () => calls++),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(AetherSwitch));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Cancel')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(140, 70));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('keyboard activates focused control once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(AetherButton(label: 'Keyboard', onPressed: () => calls++)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, 2);
  });

  testWidgets('dropdown and menu accept the first click and dismiss cleanly', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      _app(
        Center(
          child: AetherDropdown<int>(
            width: 220,
            value: 0,
            items: const [
              AetherDropdownItem(value: 0, label: 'Open menu'),
              AetherDropdownItem(value: 1, label: 'Choose'),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    expect(selected, 1);
    await tester.pumpAndSettle();
    expect(find.text('Choose'), findsNothing);
  });

  testWidgets(
    'search clear has a usable button target and clears immediately',
    (tester) async {
      final controller = TextEditingController(text: 'Track');
      var changes = 0;
      await tester.pumpWidget(
        _app(
          AetherSearchField(
            controller: controller,
            onChanged: (_) => changes++,
          ),
        ),
      );
      await tester.tap(find.byTooltip('清空'));
      expect(controller.text, isEmpty);
      expect(changes, 1);
      await tester.pumpAndSettle();
      expect(find.byTooltip('清空'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: buildAetheriaThemeData(AppThemeConfig.dark),
  home: Scaffold(body: child),
);

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}
