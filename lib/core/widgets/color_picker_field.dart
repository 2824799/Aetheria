import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';

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

  void _openCustomColorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CustomColorDialog(
        initialColor: widget.value,
        cfg: widget.cfg,
        onConfirm: (hex) => widget.onChanged(hex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final selected = _normalizeHex(widget.value);
    final isPreset = _presetColors.any((c) => c.toLowerCase() == selected.toLowerCase());

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._presetColors.map((colorHex) {
          final color = _parseHexColor(colorHex);
          final isSelected = selected.toLowerCase() == colorHex.toLowerCase();
          return InkWell(
            onTap: () => widget.onChanged(colorHex),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? cfg.textMain : Colors.white.withOpacity(0.18),
                  width: isSelected ? 2.2 : 1,
                ),
              ),
            ),
          );
        }),
        InkWell(
          onTap: _openCustomColorDialog,
          borderRadius: BorderRadius.circular(6),
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
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPreset ? Colors.white.withOpacity(0.18) : cfg.textMain,
                width: isPreset ? 1 : 2.2,
              ),
            ),
            child: isPreset
                ? Icon(Icons.color_lens, size: 14, color: cfg.textSub)
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
  final ValueChanged<String> onConfirm;

  const _CustomColorDialog({
    required this.initialColor,
    required this.cfg,
    required this.onConfirm,
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
    _red = color.red.toDouble();
    _green = color.green.toDouble();
    _blue = color.blue.toDouble();
    _hexController = TextEditingController(text: _normalizeHex(widget.initialColor));
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
    final hex = '#${_red.round().toRadixString(16).padLeft(2, '0')}'
        '${_green.round().toRadixString(16).padLeft(2, '0')}'
        '${_blue.round().toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
    _hexController.text = hex;
  }

  void _applyHex(String value) {
    final normalized = _normalizeHex(value);
    final color = _parseHexColor(normalized);
    setState(() {
      _red = color.red.toDouble();
      _green = color.green.toDouble();
      _blue = color.blue.toDouble();
      _hexController.text = normalized;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    return AlertDialog(
      backgroundColor: cfg.bgPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('自定义颜色', style: TextStyle(color: cfg.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, _red.round(), _green.round(), _blue.round()),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cfg.border),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  height: 36,
                  child: TextField(
                    controller: _hexController,
                    style: TextStyle(color: cfg.textMain, fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.08),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cfg.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cfg.border)),
                    ),
                    onSubmitted: _applyHex,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildChannelSlider('R', _red, Colors.redAccent, (v) => setState(() { _red = v; _emitFromRgb(); })),
            _buildChannelSlider('G', _green, Colors.greenAccent, (v) => setState(() { _green = v; _emitFromRgb(); })),
            _buildChannelSlider('B', _blue, Colors.blueAccent, (v) => setState(() { _blue = v; _emitFromRgb(); })),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: cfg.textSub)),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(_normalizeHex(_hexController.text));
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(backgroundColor: cfg.accent, foregroundColor: Colors.white),
          child: const Text('确定'),
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
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              color: widget.cfg.textSub,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            inactiveColor: widget.cfg.border,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(color: widget.cfg.textSub, fontSize: 10),
          ),
        ),
      ],
    );
  }
}
