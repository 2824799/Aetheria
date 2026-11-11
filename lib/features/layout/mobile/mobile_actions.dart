import 'package:flutter/material.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';

Future<void> mobileShowPlayErrorDialog(BuildContext context, Object error) {
  return showAetherDialog<void>(
    context: context,
    builder: (ctx) => AetherDialog(
      title: '播放失败 - 诊断报告',
      content: SelectableText(
        error.toString(),
        style: AetherType.captionStyle(
          ctx.tokens.textSecondary,
        ).copyWith(fontFamily: 'monospace'),
      ),
      actions: [
        AetherButton.primary(
          label: '关闭',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}
