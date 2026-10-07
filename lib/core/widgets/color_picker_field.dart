import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';

Color? parsePickerColor(String value) {
  final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
    return null;
  }
  return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
}

String pickerColorHex(Color color, {bool includeAlpha = false}) {
  final value = color.toARGB32();
  return '#${(includeAlpha ? value : value & 0xffffff).toRadixString(16).padLeft(includeAlpha ? 8 : 6, '0').toUpperCase()}';
}

class ColorPickerField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final AppThemeConfig cfg;
  final bool showPresets;
  final bool enableAlpha;
  final bool livePreview;
  final ValueChanged<String>? onPreview;

  const ColorPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.cfg,
    this.showPresets = true,
    this.enableAlpha = false,
    this.livePreview = false,
    this.onPreview,
  });

  @override
  State<ColorPickerField> createState() => _ColorPickerFieldState();
}

class _ColorPickerFieldState extends State<ColorPickerField> {
  static const _presets = [
    0xffef4444,
    0xff3b82f6,
    0xfff43f5e,
    0xff10b981,
    0xfff59e0b,
    0xffec4899,
    0xff84cc16,
    0xff64748b,
    0xff8b5cf6,
    0xff06b6d4,
    0xffeab308,
  ];

  Future<void> _open() async {
    final original = widget.value;
    final onChanged = widget.onChanged;
    final onPreview = widget.livePreview
        ? (widget.onPreview ?? onChanged)
        : null;
    final result = await showAetherDialog<String>(
      context: context,
      builder: (_) => _CustomColorDialog(
        initialColor: original,
        cfg: widget.cfg,
        enableAlpha: widget.enableAlpha,
        onPreview: onPreview,
      ),
    );
    if (result != null) {
      onChanged(result);
    } else {
      onPreview?.call(original);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = parsePickerColor(widget.value) ?? const Color(0xff3b82f6);
    return Wrap(
      spacing: AetherSpace.sm,
      runSpacing: AetherSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.showPresets)
          for (final value in _presets)
            AetherPressable(
              tooltip: pickerColorHex(Color(value)),
              onTap: () => widget.onChanged(pickerColorHex(Color(value))),
              borderRadius: BorderRadius.circular(AetherRadius.sm),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(value),
                  borderRadius: BorderRadius.circular(AetherRadius.sm),
                  border: Border.all(
                    color: selected.toARGB32() == value
                        ? widget.cfg.textPrimary
                        : widget.cfg.borderSubtle,
                    width: selected.toARGB32() == value ? 2 : 1,
                  ),
                ),
              ),
            ),
        AetherButton.secondary(
          label:
              '自定义 ${pickerColorHex(selected, includeAlpha: widget.enableAlpha)}',
          icon: Icons.color_lens_outlined,
          size: AetherButtonSize.sm,
          onPressed: _open,
        ),
      ],
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  final String initialColor;
  final AppThemeConfig cfg;
  final bool enableAlpha;
  final ValueChanged<String>? onPreview;
  const _CustomColorDialog({
    required this.initialColor,
    required this.cfg,
    required this.enableAlpha,
    this.onPreview,
  });
  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late final TextEditingController _hex;
  late HSVColor _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    _color = HSVColor.fromColor(
      parsePickerColor(widget.initialColor) ?? const Color(0xff3b82f6),
    );
    _hex = TextEditingController(text: _value);
  }

  String get _value =>
      pickerColorHex(_color.toColor(), includeAlpha: widget.enableAlpha);
  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _change(HSVColor color) {
    setState(() {
      _color = color;
      _error = null;
      _hex.text = _value;
    });
    widget.onPreview?.call(_value);
  }

  void _typed(String value) {
    final parsed = parsePickerColor(value);
    final valid =
        parsed != null &&
        (widget.enableAlpha || value.trim().replaceFirst('#', '').length == 6);
    setState(() {
      _error = valid
          ? null
          : (widget.enableAlpha ? '请输入 #RRGGBB 或 #AARRGGBB' : '请输入 #RRGGBB');
      if (valid) {
        _color = HSVColor.fromColor(parsed);
      }
    });
    if (valid) widget.onPreview?.call(_value);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    return AetherDialog(
      title: '自定义颜色',
      maxWidth: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              void pick(Offset position) => _change(
                _color
                    .withSaturation(
                      (position.dx / constraints.maxWidth).clamp(0, 1),
                    )
                    .withValue((1 - position.dy / 155).clamp(0, 1)),
              );
              return Semantics(
                label: '饱和度与明度色板',
                child: GestureDetector(
                  key: const ValueKey('color-sv-plane'),
                  onPanDown: (event) => pick(event.localPosition),
                  onPanUpdate: (event) => pick(event.localPosition),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 155),
                    painter: _SaturationValuePainter(_color),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _slider(
            '色相',
            _color.hue,
            360,
            (value) => _change(_color.withHue(value)),
            color: HSVColor.fromAHSV(1, _color.hue, 1, 1).toColor(),
          ),
          if (widget.enableAlpha)
            _slider(
              '不透明度',
              _color.alpha * 100,
              100,
              (value) => _change(_color.withAlpha(value / 100)),
            ),
          Row(
            children: [
              for (final background in [
                const Color(0xff171717),
                const Color(0xffeeeeee),
              ])
                Expanded(
                  child: Container(
                    color: background,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '歌词 Aa',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _color.toColor(),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AetherTextField(
            key: const ValueKey('color-hex'),
            controller: _hex,
            label: widget.enableAlpha ? '颜色值（8 位格式前两位为透明度）' : '颜色值',
            hintText: widget.enableAlpha ? '#AARRGGBB' : '#RRGGBB',
            onChanged: _typed,
            onSubmitted: _typed,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: TextStyle(color: cfg.accent)),
            ),
          if (widget.onPreview != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '实时预览，取消可恢复原颜色',
                style: AetherType.captionStyle(cfg.textSecondary),
              ),
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
          onPressed: _error != null
              ? null
              : () => Navigator.of(context).pop(_value),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> change, {
    Color? color,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: AetherType.captionStyle(widget.cfg.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            activeColor: color,
            onChanged: change,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${value.round()}${max == 100 ? '%' : '°'}',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  final HSVColor color;
  _SaturationValuePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final point = Offset(
      color.saturation * size.width,
      (1 - color.value) * size.height,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.color != color;
}
