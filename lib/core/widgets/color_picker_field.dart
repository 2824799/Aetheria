import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';

class ColorPickerField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final AppThemeConfig cfg;

  const ColorPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.cfg,
  });

  @override
  State<ColorPickerField> createState() => _ColorPickerFieldState();
}

class _ColorPickerFieldState extends State<ColorPickerField> {
  static const _presetColors = [
    '#ef4444',
    '#3b82f6',
    '#f43f5e',
    '#10b981',
    '#f59e0b',
    '#ec4899',
    '#84cc16',
    '#64748b',
    '#8b5cf6',
    '#06b6d4',
    '#eab308',
  ];

  Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF3B82F6);
  }

  String _normalizeHex(String hex) {
    final clean = hex.replaceAll('#', '').toUpperCase();
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return '#$clean';
    return '#3B82F6';
  }

  Future<void> _openCustomColorDialog() async {
    final result = await showAetherDialog<String>(
      context: context,
      builder: (ctx) => _CustomColorDialog(
        initialColor: widget.value,
        cfg: widget.cfg,
      ),
    );
    if (result != null) {
      widget.onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final selected = _normalizeHex(widget.value);
    final isPreset = _presetColors.any(
      (c) => c.toLowerCase() == selected.toLowerCase(),
    );

    return Wrap(
      spacing: AetherSpace.md,
      runSpacing: AetherSpace.md,
      children: [
        ..._presetColors.map((colorHex) {
          final color = _parseHexColor(colorHex);
          final isSelected = selected.toLowerCase() == colorHex.toLowerCase();
          return AetherPressable(
            onTap: () => widget.onChanged(colorHex),
            borderRadius: BorderRadius.circular(AetherRadius.sm),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AetherRadius.sm),
                border: Border.all(
                  color: isSelected
                      ? cfg.textPrimary
                      : cfg.borderSubtle.withValues(alpha: 0.9),
                  width: isSelected ? 2.2 : 1,
                ),
              ),
            ),
          );
        }),
        AetherPressable(
          onTap: _openCustomColorDialog,
          borderRadius: BorderRadius.circular(AetherRadius.sm),
          tooltip: '自定义颜色',
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: isPreset
                  ? null
                  : const LinearGradient(
                      colors: [Colors.red, Colors.green, Colors.blue],
                    ),
              color: isPreset ? cfg.bgHover : null,
              borderRadius: BorderRadius.circular(AetherRadius.sm),
              border: Border.all(
                color: isPreset
                    ? cfg.borderSubtle.withValues(alpha: 0.9)
                    : cfg.textPrimary,
                width: isPreset ? 1 : 2.2,
              ),
            ),
            child: isPreset
                ? Icon(Icons.color_lens, size: 14, color: cfg.textSecondary)
                : const Icon(Icons.check, size: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  final String initialColor;
  final AppThemeConfig cfg;

  const _CustomColorDialog({
    required this.initialColor,
    required this.cfg,
  });

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late final TextEditingController _hexController;
  late double _red;
  late double _green;
  late double _blue;

  @override
  void initState() {
    super.initState();
    final color = _parseHexColor(widget.initialColor);
    _red = (color.r * 255.0);
    _green = (color.g * 255.0);
    _blue = (color.b * 255.0);
    _hexController = TextEditingController(
      text: _normalizeHex(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF3B82F6);
  }

  String _normalizeHex(String hex) {
    final clean = hex.replaceAll('#', '').toUpperCase();
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return '#$clean';
    return '#3B82F6';
  }

  void _emitFromRgb() {
    final hex =
        '#${_red.round().toRadixString(16).padLeft(2, '0')}'
        '${_green.round().toRadixString(16).padLeft(2, '0')}'
        '${_blue.round().toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
    _hexController.text = hex;
  }

  void _applyHex(String value) {
    final normalized = _normalizeHex(value);
    final color = _parseHexColor(normalized);
    setState(() {
      _red = color.r * 255.0;
      _green = color.g * 255.0;
      _blue = color.b * 255.0;
      _hexController.text = normalized;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    return AetherDialog(
      title: '自定义颜色',
      maxWidth: 320,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    _red.round(),
                    _green.round(),
                    _blue.round(),
                  ),
                  borderRadius: BorderRadius.circular(AetherRadius.sm),
                  border: Border.all(color: cfg.borderSubtle),
                ),
              ),
              const SizedBox(width: AetherSpace.lg),
              Expanded(
                child: AetherTextField(
                  controller: _hexController,
                  hintText: '#RRGGBB',
                  height: AetherSpace.controlHeight,
                  onSubmitted: _applyHex,
                ),
              ),
            ],
          ),
          const SizedBox(height: AetherSpace.xl),
          _buildChannelSlider(
            'R',
            _red,
            Colors.redAccent,
            (v) => setState(() {
              _red = v;
              _emitFromRgb();
            }),
          ),
          _buildChannelSlider(
            'G',
            _green,
            Colors.green,
            (v) => setState(() {
              _green = v;
              _emitFromRgb();
            }),
          ),
          _buildChannelSlider(
            'B',
            _blue,
            Colors.blueAccent,
            (v) => setState(() {
              _blue = v;
              _emitFromRgb();
            }),
          ),
        ],
      ),
      actions: [
        AetherButton.ghost(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AetherButton.primary(
          label: '确定',
          onPressed: () {
            Navigator.of(context).pop(_normalizeHex(_hexController.text));
          },
        ),
      ],
    );
  }

  Widget _buildChannelSlider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text(
              label,
              style: AetherType.labelStyle(widget.cfg.textSecondary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: widget.cfg.sliderTrack,
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(0, 255),
                min: 0,
                max: 255,
                divisions: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.right,
              style: AetherType.captionStyle(widget.cfg.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
