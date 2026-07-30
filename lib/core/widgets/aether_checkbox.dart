import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';

/// Compact themed checkbox used in import previews and bulk select UIs.
class AetherCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final double size;

  const AetherCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: Checkbox(
        value: value,
        onChanged: onChanged,
        activeColor: cfg.accent,
        checkColor: cfg.onAccent,
        side: BorderSide(color: cfg.borderStrong),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
