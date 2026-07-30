import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_shared.dart';

class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.content,
    required this.offsetMs,
    required this.cfg,
    this.translation,
    this.compact = false,
    this.allowSeekGuide = true,
  });

  final String content;
  final String? translation;
  final int offsetMs;
  final AppThemeConfig cfg;
  final bool compact;
  final bool allowSeekGuide;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _controller = ScrollController();
  Timer? _guideTimer;
  int _lastActiveIndex = -1;
  bool _guideVisible = false;
  bool _autoScrolling = false;

  double get _lineExtent => widget.compact ? 72 : 84;

  @override
  void dispose() {
    _guideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final lines = parseLyrics(widget.content);
    final translation = translationByTime(widget.translation);
    final timed = lines.any((line) => line.timeMs != null);
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: widget.cfg.textSecondary, fontSize: AetherType.body),
        ),
      );
    }

    final activeIndex = timed
        ? activeLyricLineIndex(
            lines,
            audio.currentPosition.inMilliseconds + widget.offsetMs,
          )
        : -1;
    if (activeIndex != _lastActiveIndex && !_guideVisible) {
      _lastActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || activeIndex < 0) {
          return;
        }
        _autoScrollToIndex(activeIndex);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (!widget.allowSeekGuide || _autoScrolling) {
                  return false;
                }
                if (notification is ScrollStartNotification ||
                    notification is ScrollUpdateNotification) {
                  _showSeekGuide();
                }
                return false;
              },
              child: ListView.builder(
                controller: _controller,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 18 : 24,
                  vertical: math.max(
                    18,
                    constraints.maxHeight / 2 - _lineExtent / 2,
                  ),
                ),
                itemExtent: _lineExtent,
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index];
                  final active = index == activeIndex;
                  final lineTranslation = line.timeMs == null
                      ? null
                      : translation[line.timeMs]?.trim();
                  return LyricLineTile(
                    line: line,
                    translation: lineTranslation,
                    active: active,
                    cfg: widget.cfg,
                    compact: widget.compact,
                  );
                },
              ),
            ),
            if (widget.allowSeekGuide && _guideVisible)
              LyricSeekGuideOverlay(
                cfg: widget.cfg,
                onSeek: timed ? () => _seekToGuideLine(lines) : null,
              ),
          ],
        );
      },
    );
  }

  void _autoScrollToIndex(int index) {
    if (!_controller.hasClients) {
      return;
    }
    final target = math.max(0.0, index * _lineExtent);
    final clamped = math.min(target, _controller.position.maxScrollExtent);
    if (AetherMotion.reduce(context)) {
      _controller.jumpTo(clamped);
      return;
    }
    _autoScrolling = true;
    _controller
        .animateTo(
          clamped,
          duration: AetherMotion.panel,
          curve: AetherMotion.out,
        )
        .whenComplete(() {
          _autoScrolling = false;
        });
  }

  void _showSeekGuide() {
    _guideTimer?.cancel();
    if (!_guideVisible) {
      setState(() {
        _guideVisible = true;
      });
    }
    _guideTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _guideVisible = false;
      });
    });
  }

  int _centerLineIndex(int count) {
    if (!_controller.hasClients || count == 0) {
      return 0;
    }
    final raw = (_controller.offset / _lineExtent).round();
    return raw.clamp(0, count - 1);
  }

  Future<void> _seekToGuideLine(List<LyricLine> lines) async {
    final index = _centerLineIndex(lines.length);
    final target = lines[index].timeMs;
    if (target == null) {
      return;
    }
    final seekMs = math.max(0, target - widget.offsetMs);
    await context.read<AudioPlayerProvider>().seek(
      Duration(milliseconds: seekMs),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _guideVisible = false;
    });
  }

}

class LyricLineTile extends StatelessWidget {
  const LyricLineTile({super.key, 
    required this.line,
    required this.translation,
    required this.active,
    required this.cfg,
    required this.compact,
  });

  final LyricLine line;
  final String? translation;
  final bool active;
  final AppThemeConfig cfg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: active ? cfg.textPrimary : cfg.textSecondary,
      fontSize: active ? (compact ? AetherType.titleSm : AetherType.title) : (compact ? AetherType.body : AetherType.body),
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      fontFamilyFallback: lyricsFontFallback,
      height: 1.24,
    );
    return AnimatedScale(
      scale: active ? 1.04 : 1.0,
      duration: AetherMotion.fast,
      curve: AetherMotion.out,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: AetherMotion.fast,
              style: baseStyle,
              child: Text(
                line.text.isEmpty ? ' ' : line.text,
                textAlign: TextAlign.center,
                softWrap: true,
                maxLines: active ? 3 : 2,
                overflow: TextOverflow.fade,
              ),
            ),
            if (translation != null && translation!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  translation!,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: active
                        ? cfg.accent
                        : cfg.textSecondary.withValues(alpha: 0.65),
                    fontSize: compact ? AetherType.caption : AetherType.bodySm,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    fontFamilyFallback: lyricsFontFallback,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LyricSeekGuideOverlay extends StatelessWidget {
  const LyricSeekGuideOverlay({super.key, required this.cfg, required this.onSeek});

  final AppThemeConfig cfg;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: Row(
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: CustomPaint(
                  painter: LyricDashedLinePainter(
                    cfg.accent.withValues(alpha: 0.55),
                  ),
                  child: const SizedBox(height: 1),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: cfg.accent.withValues(alpha: 0.14),
                shape: const CircleBorder(),
                child: AetherIconButton(
                  icon: Icons.play_arrow,
                  size: 34,
                  iconSize: AetherIconSize.lg,
                  color: cfg.accent,
                  tooltip: '从这里播放',
                  onPressed: onSeek,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class LyricDashedLinePainter extends CustomPainter {
  const LyricDashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 6.0;
    const dashGap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + dashWidth, size.width), 0),
        paint,
      );
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant LyricDashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

