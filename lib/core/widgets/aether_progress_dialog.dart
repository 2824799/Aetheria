import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';

class AetherProgressUpdate {
  final String title;
  final String? detail;
  final double? value; // null = indeterminate

  const AetherProgressUpdate({
    required this.title,
    this.detail,
    this.value,
  });
}

typedef AetherProgressTask<T> = Future<T> Function(
  void Function(AetherProgressUpdate update) report,
);

Future<T?> showAetherProgressDialog<T>({
  required BuildContext context,
  required String title,
  required AetherProgressTask<T> task,
  bool barrierDismissible = false,
}) {
  return showAetherDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      return _AetherProgressDialogBody<T>(
        initialTitle: title,
        task: task,
      );
    },
  );
}

class _AetherProgressDialogBody<T> extends StatefulWidget {
  final String initialTitle;
  final AetherProgressTask<T> task;

  const _AetherProgressDialogBody({
    required this.initialTitle,
    required this.task,
  });

  @override
  State<_AetherProgressDialogBody<T>> createState() =>
      _AetherProgressDialogBodyState<T>();
}

class _AetherProgressDialogBodyState<T>
    extends State<_AetherProgressDialogBody<T>> {
  late String _title = widget.initialTitle;
  String? _detail;
  double? _value;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final result = await widget.task((update) {
        if (!mounted) return;
        setState(() {
          _title = update.title;
          _detail = update.detail;
          _value = update.value;
        });
      });
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;

    if (_error != null) {
      return AetherDialog(
        title: '出错了',
        content: Text(
          _error.toString(),
          style: AetherType.bodyStyle(cfg.danger),
        ),
        actions: [
          AetherButton.primary(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return AetherDialog(
      title: _title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_detail != null) ...[
            Text(_detail!, style: AetherType.bodySmStyle(cfg.textSecondary)),
            const SizedBox(height: AetherSpace.lg),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _value?.clamp(0.0, 1.0),
              backgroundColor: cfg.sliderTrack,
              color: cfg.accent,
            ),
          ),
        ],
      ),
    );
  }
}
