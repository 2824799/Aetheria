import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';

/// Shared slider look for transport, volume, offsets, settings.
class AetherSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final double trackHeight;
  final double thumbRadius;

  const AetherSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor,
    this.trackHeight = 3,
    this.thumbRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final active = activeColor ?? cfg.accent;
    final clamped = value.clamp(min, max);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        activeTrackColor: active,
        inactiveTrackColor: cfg.sliderTrack,
        thumbColor: active,
        overlayColor: active.withValues(alpha: 0.16),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
        overlayShape: RoundSliderOverlayShape(overlayRadius: thumbRadius + 8),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: clamped.toDouble(),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// Thin top-edge progress used by PlayBar. 1:1 drag, no fancy animation.
class AetherSeekBar extends StatelessWidget {
  final double progress;
  final ValueChanged<double> onSeek;
  final double height;

  const AetherSeekBar({
    super.key,
    required this.progress,
    required this.onSeek,
    this.height = 4,
  });

  void _handle(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final pct = (local.dx / box.size.width).clamp(0.0, 1.0);
    onSeek(pct);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final p = progress.clamp(0.0, 1.0);

    return SizedBox(
      height: height + 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => _handle(context, d.globalPosition),
          onTapDown: (d) => _handle(context, d.globalPosition),
          child: Center(
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Stack(
                children: [
                  Container(color: cfg.sliderTrack),
                  FractionallySizedBox(
                    widthFactor: p,
                    child: AnimatedContainer(
                      duration: AetherMotion.duration(context, AetherMotion.press),
                      curve: AetherMotion.curve(context),
                      color: cfg.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
