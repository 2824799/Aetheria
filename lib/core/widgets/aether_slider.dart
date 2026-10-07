import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';

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
class AetherSeekBar extends StatefulWidget {
  final double progress;
  final FutureOr<void> Function(double) onSeek;
  final double height;

  const AetherSeekBar({
    super.key,
    required this.progress,
    required this.onSeek,
    this.height = 4,
  });

  @override
  State<AetherSeekBar> createState() => _AetherSeekBarState();
}

class _AetherSeekBarState extends State<AetherSeekBar> {
  double? _preview;
  int _seekRequest = 0;

  void _updatePreview(Offset position) {
    _seekRequest++;
    setState(() => _preview = _progressAt(position));
  }

  Future<void> _commit(double progress) async {
    final request = ++_seekRequest;
    setState(() => _preview = progress);
    try {
      await widget.onSeek(progress);
    } finally {
      if (mounted && request == _seekRequest) {
        setState(() => _preview = null);
      }
    }
  }

  double _progressAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    if (box.size.width <= 0) return 0;
    return (box.globalToLocal(globalPosition).dx / box.size.width).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final p = (_preview ?? widget.progress).clamp(0.0, 1.0);

    return SizedBox(
      height: widget.height + 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _updatePreview(d.globalPosition),
          onHorizontalDragUpdate: (d) => _updatePreview(d.globalPosition),
          onHorizontalDragEnd: (_) {
            final target = _preview;
            if (target != null) _commit(target);
          },
          onHorizontalDragCancel: () => setState(() => _preview = null),
          onTapUp: (d) => _commit(_progressAt(d.globalPosition)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final diameter = constraints.maxWidth.clamp(0.0, 10.0);
              final left = (constraints.maxWidth * p - diameter / 2).clamp(
                0.0,
                constraints.maxWidth - diameter,
              );
              return Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: SizedBox(
                      height: widget.height,
                      width: double.infinity,
                      child: Stack(
                        children: [
                          Container(color: cfg.sliderTrack),
                          FractionallySizedBox(
                            widthFactor: p,
                            // ColoredBox needs an explicit track height.
                            heightFactor: 1,
                            child: ColoredBox(color: cfg.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: left,
                    width: diameter,
                    height: diameter,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('aether-seek-thumb'),
                        decoration: BoxDecoration(
                          color: cfg.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
