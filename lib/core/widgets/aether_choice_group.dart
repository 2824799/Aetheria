import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/widgets/aether_chip.dart';

class AetherChoiceOption<T> {
  final T value;
  final String label;
  final Widget? leading;
  final String? tooltip;

  const AetherChoiceOption({
    required this.value,
    required this.label,
    this.leading,
    this.tooltip,
  });
}

/// Single-select chip group. Prefer over raw [ChoiceChip].
class AetherChoiceGroup<T> extends StatelessWidget {
  final List<AetherChoiceOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final bool enabled;
  final bool compact;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  const AetherChoiceGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.compact = true,
    this.spacing = AetherSpace.sm,
    this.runSpacing = AetherSpace.sm,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      children: [
        for (final option in options)
          AetherChip(
            label: option.label,
            leading: option.leading,
            compact: compact,
            state: option.value == value
                ? AetherChipState.selected
                : AetherChipState.idle,
            onTap: !enabled || onChanged == null
                ? null
                : () => onChanged!(option.value),
          ),
      ],
    );
  }
}
