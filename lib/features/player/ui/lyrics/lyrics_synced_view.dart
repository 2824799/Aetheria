import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/lyrics/lyric_timeline.dart';
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
  late LyricTimeline _timeline;
  Timer? _guideTimer;
  int _lastActiveIndex = -1;
  bool _guideVisible = false;
  bool _autoScrolling = false;
  ValueListenable<Duration>? _position;
  bool _visible = true;

  double get _lineExtent => widget.compact ? 72 : 84;

  @override
  void initState() {
    super.initState();
    _parseTimeline();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.translation != widget.translation) {
      _parseTimeline();
      _lastActiveIndex = -1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final position = context.read<AudioPlayerProvider>().positionListenable;
    if (!identical(position, _position)) {
      _position?.removeListener(_onPositionChanged);
      _position = position..addListener(_onPositionChanged);
    }
  }

  int get _activeIndex => _timeline.hasTimedLines
      ? LyricTimeline.activeLineIndex(
          _timeline.lines,
          (_position?.value.inMilliseconds ?? 0) + widget.offsetMs,
        )
      : -1;

  void _onPositionChanged() {
    if (mounted && _visible && _activeIndex != _lastActiveIndex) setState(() {});
  }

  void _parseTimeline() {
    _timeline = LyricTimeline.parse(
      content: widget.content,
      translation: widget.translation,
    );
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    _position?.removeListener(_onPositionChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    final lines = timeline.lines;
    final timed = timeline.hasTimedLines;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: AetherType.bodyStyle(widget.cfg.textSecondary),
        ),
      );
    }

    final activeIndex = _activeIndex;
    final activeChanged = activeIndex != _lastActiveIndex;
    _lastActiveIndex = activeIndex;
    if (activeChanged && !_guideVisible) {
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
                  final lineTranslation = timeline.translationFor(line);
                  return LyricLineTile(
                    line: line,
                    translation: lineTranslation.isEmpty
                        ? null
                        : lineTranslation,
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
          duration: AetherMotion.duration(context, AetherMotion.panel),
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
        _lastActiveIndex = -1;
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
  const LyricLineTile({
    super.key,
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
      fontSize: active
          ? (compact ? AetherType.titleSm : AetherType.title)
          : (compact ? AetherType.body : AetherType.body),
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      fontFamilyFallback: lyricsFontFallback,
      height: 1.24,
    );
    return AnimatedScale(
      scale: active ? 1.04 : 1.0,
      duration: AetherMotion.duration(context, AetherMotion.fast),
      curve: AetherMotion.out,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: AetherMotion.duration(context, AetherMotion.fast),
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
                padding: const EdgeInsets.only(top: AetherSpace.xxs),
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
  const LyricSeekGuideOverlay({
    super.key,
    required this.cfg,
    required this.onSeek,
  });

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
              const SizedBox(width: AetherSpace.xl + 2),
              Expanded(
                child: CustomPaint(
                  painter: LyricDashedLinePainter(
                    cfg.accent.withValues(alpha: 0.55),
                  ),
                  child: const SizedBox(height: 1),
                ),
              ),
              const SizedBox(width: AetherSpace.md),
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
              const SizedBox(width: AetherSpace.lg),
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
