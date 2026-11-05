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
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;
  int _lastActiveIndex = -1;
  bool _guideVisible = false;
  bool _autoScrolling = false;
  ValueListenable<Duration>? _position;
  bool _visible = true;

  bool get _hasTranslation =>
      _timeline.translationByTime.isNotEmpty ||
      _timeline.lines.any((l) => l.translation != null && l.translation!.isNotEmpty);

  double get _lineExtent {
    if (_hasTranslation) {
      return widget.compact ? 44.0 : 50.0;
    }
    return widget.compact ? 30.0 : 34.0;
  }

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
      _guideVisible = false;
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
        final centerHeight = math.max(34.0, _lineExtent);
        final centerY = constraints.maxHeight / 2;
        final centerHalf = centerHeight / 2;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _pointerDownPos = event.localPosition;
            _pointerDownTime = DateTime.now();
          },
          onPointerUp: (event) {
            if (!_guideVisible || _pointerDownPos == null) {
              return;
            }
            final moved = (event.localPosition - _pointerDownPos!).distance;
            final elapsed = _pointerDownTime == null
                ? Duration.zero
                : DateTime.now().difference(_pointerDownTime!);
            if (moved < 12 && elapsed < const Duration(milliseconds: 500)) {
              final y = event.localPosition.dy;
              if (y < centerY - centerHalf || y > centerY + centerHalf) {
                _recycleToActivePosition();
              }
            }
          },
          child: MouseRegion(
            cursor: _guideVisible ? SystemMouseCursors.click : MouseCursor.defer,
            child: Stack(
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
                  Positioned(
                    top: math.max(0.0, centerY - centerHalf),
                    left: 0,
                    right: 0,
                    height: centerHeight,
                    child: LyricSeekGuideOverlay(
                      cfg: widget.cfg,
                      onSeek: timed ? () => _seekToGuideLine(lines) : null,
                    ),
                  ),
              ],
            ),
          ),
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
    if (!_guideVisible) {
      setState(() {
        _guideVisible = true;
      });
    }
  }

  void _recycleToActivePosition() {
    if (!_guideVisible) {
      return;
    }
    setState(() {
      _guideVisible = false;
      _lastActiveIndex = -1;
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
      _lastActiveIndex = -1;
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
      color: active ? cfg.textPrimary : cfg.textSecondary.withValues(alpha: 0.75),
      fontSize: active
          ? (compact ? AetherType.titleSm : AetherType.title)
          : (compact ? AetherType.bodySm : AetherType.body),
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      fontFamilyFallback: lyricsFontFallback,
      height: 1.22,
    );
    final isBlank = line.text.trim().isEmpty;
    final textToShow = isBlank ? (active ? '···' : ' ') : line.text;

    return AnimatedScale(
      scale: active ? 1.05 : 1.0,
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
                textToShow,
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
                        : cfg.textSecondary.withValues(alpha: 0.55),
                    fontSize: compact ? AetherType.caption : AetherType.bodySm,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    fontFamilyFallback: lyricsFontFallback,
                    height: 1.15,
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
    return Center(
      child: Row(
        children: [
          const SizedBox(width: AetherSpace.xl + 2),
          Expanded(
            child: IgnorePointer(
              child: CustomPaint(
                painter: LyricDashedLinePainter(
                  cfg.accent.withValues(alpha: 0.55),
                ),
                child: const SizedBox(height: 1),
              ),
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
