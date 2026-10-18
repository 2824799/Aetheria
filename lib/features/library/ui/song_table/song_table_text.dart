import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

enum SongTableTextGroup { title, titleWithoutLyrics, artist }

typedef _TextSpec = ({
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
  Locale? locale,
  TextAlign align,
  int? lines,
  TextOverflow overflow,
  bool wrap,
  TextHeightBehavior? heightBehavior,
  SongTableTextGroup? group,
});
typedef _LayoutKey = (_TextSpec, double, double);

/// Retain shaped text when virtualized rows leave the viewport. Widget reuse
/// alone does not retain RenderParagraph's layout after a row is unmounted.
class SongTableTextCache extends ChangeNotifier {
  SongTableTextCache({this.capacity = 2048}) : assert(capacity > 0) {
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }
  final int capacity;
  final _layouts = <_LayoutKey, _TextLayout>{};
  bool _disposed = false;
  final _warmFormats = <_LayoutKey>{};
  final _warmQueue = Queue<(_TextSpec, BoxConstraints, Iterator<String>)>();
  final _clock = Stopwatch()..start();
  Object? _sourceRevision;
  Map<SongTableTextGroup, List<String>> _sources = {};
  Timer? _warmTimer;
  int _resumeAfter = 0;
  int _layoutMisses = 0;
  int _idleLayouts = 0;

  int get cachedLayouts => _layouts.length;
  int get layoutMisses => _layoutMisses;
  int get idleLayouts => _idleLayouts;
  int get pendingWarmupFormats => _warmQueue.length;

  /// Prepare offscreen labels in small idle slices, never in a scroll frame.
  void configurePrefetch({
    required Object revision,
    required Iterable<String> titles,
    Iterable<String> titlesWithoutLyrics = const [],
    required Iterable<String> artists,
  }) {
    if (identical(revision, _sourceRevision)) return;
    _sourceRevision = revision;
    final sources = {
      SongTableTextGroup.title: titles.toSet().take(capacity ~/ 3).toList(),
      SongTableTextGroup.titleWithoutLyrics: titlesWithoutLyrics
          .toSet()
          .take(capacity ~/ 3)
          .toList(),
      SongTableTextGroup.artist: artists.toSet().take(capacity ~/ 3).toList(),
    };
    if (sources.keys.every(
      (group) => listEquals(sources[group], _sources[group]),
    )) {
      return;
    }
    _sources = sources;
    final formats = _warmFormats.toList();
    _warmFormats.clear();
    _warmQueue.clear();
    // Providers can return a fresh list with unchanged content. Preserve its
    // work above; when content changes, reuse the known geometry even if the
    // currently visible labels themselves do not need another layout.
    for (final format in formats) {
      _queueWarmup(
        format.$1,
        BoxConstraints(minWidth: format.$2, maxWidth: format.$3),
      );
    }
  }

  void deferWarmup() => _resumeAfter = _clock.elapsedMilliseconds + 200;

  _TextSpec _withText(_TextSpec spec, String text) => (
    text: text,
    style: spec.style,
    scaler: spec.scaler,
    direction: spec.direction,
    locale: spec.locale,
    align: spec.align,
    lines: spec.lines,
    overflow: spec.overflow,
    wrap: spec.wrap,
    heightBehavior: spec.heightBehavior,
    group: spec.group,
  );

  void _queueWarmup(_TextSpec spec, BoxConstraints constraints) {
    final source = _sources[spec.group];
    if (source == null || source.isEmpty || _disposed) return;
    final key = (
      _withText(spec, ''),
      constraints.minWidth,
      constraints.maxWidth,
    );
    if (_warmFormats.length >= 8 && !_warmFormats.contains(key)) {
      _warmFormats.clear();
      _warmQueue.clear();
    }
    if (!_warmFormats.add(key)) return;
    _warmQueue.add((spec, constraints, source.iterator));
    _scheduleWarmup();
  }

  void _scheduleWarmup([int delayMs = 1]) {
    if (_disposed || _warmTimer != null || _warmQueue.isEmpty) return;
    _warmTimer = Timer(Duration(milliseconds: delayMs), _warmOne);
  }

  void _warmOne() {
    _warmTimer = null;
    if (_disposed || _warmQueue.isEmpty) return;
    final scheduler = SchedulerBinding.instance;
    // A playing progress indicator may schedule frames indefinitely. Only
    // yield for actual interaction and an executing frame, so playback cannot
    // starve preparation of the next rows. Check a 0.75ms budget between
    // labels; an individual native paragraph layout cannot be preempted.
    if (_clock.elapsedMilliseconds < _resumeAfter ||
        scheduler.schedulerPhase != SchedulerPhase.idle) {
      _scheduleWarmup(16);
      return;
    }
    final start = _clock.elapsedMicroseconds;
    for (var count = 0; count < 4 && _warmQueue.isNotEmpty; count++) {
      final job = _warmQueue.first;
      if (job.$3.moveNext()) {
        final previousMisses = _layoutMisses;
        _acquire(_withText(job.$1, job.$3.current), job.$2).release();
        _idleLayouts += _layoutMisses - previousMisses;
      } else {
        _warmQueue.removeFirst();
      }
      if (_clock.elapsedMicroseconds - start >= 750) break;
    }
    _scheduleWarmup();
  }

  _TextLayout _acquire(_TextSpec spec, BoxConstraints constraints) {
    final maxWidth = spec.wrap || spec.overflow == TextOverflow.ellipsis
        ? constraints.maxWidth
        : double.infinity;
    final key = (spec, constraints.minWidth, maxWidth);
    var entry = _layouts.remove(key);
    if (entry == null) {
      _layoutMisses++;
      final painter = TextPainter(
        text: TextSpan(text: spec.text, style: spec.style),
        textAlign: spec.align,
        textDirection: spec.direction,
        textScaler: spec.scaler,
        locale: spec.locale,
        maxLines: spec.lines,
        ellipsis: spec.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        textHeightBehavior: spec.heightBehavior,
      )..layout(minWidth: constraints.minWidth, maxWidth: maxWidth);
      entry = _TextLayout(painter);
    }
    entry.users++;
    if (!_disposed) {
      _layouts[key] = entry;
      if (_layouts.length > capacity) {
        _layouts.remove(_layouts.keys.first)!._evict();
      }
    } else {
      entry.cached = false;
    }
    return entry;
  }

  void _fontsChanged() {
    _warmFormats.clear();
    _warmQueue.clear();
    _clear();
    notifyListeners();
  }

  void _clear() {
    for (final entry in _layouts.values) {
      entry._evict();
    }
    _layouts.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _warmTimer?.cancel();
    _warmQueue.clear();
    _sources.clear();
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _clear();
    super.dispose();
  }
}

class _TextLayout {
  _TextLayout(this.painter);
  final TextPainter painter;
  int users = 0;
  bool cached = true;
  void _evict() {
    cached = false;
    if (users == 0) painter.dispose();
  }

  void release() {
    users--;
    if (users == 0 && !cached) painter.dispose();
  }
}

/// A Text-compatible table label, with the same TextPainter shaping/layout and
/// semantics. The cache is bounded and owned by the table, not a global cache.
class SongTableText extends Text {
  const SongTableText(
    super.data, {
    super.key,
    required this.cache,
    super.style,
    super.maxLines,
    super.overflow,
    super.textAlign,
    super.softWrap,
    this.prefetchGroup,
  });
  final SongTableTextCache cache;
  final SongTableTextGroup? prefetchGroup;

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = style == null || style!.inherit
        ? defaults.style.merge(style)
        : style!;
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final effectiveOverflow =
        overflow ?? effectiveStyle.overflow ?? defaults.overflow;
    // Preserve Flutter's selection, spacing accessibility overrides and fade
    // behavior when those features are requested outside ordinary table cells.
    if (SelectionContainer.maybeOf(context) != null ||
        defaults.textWidthBasis != TextWidthBasis.parent ||
        effectiveOverflow == TextOverflow.fade ||
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context) != null ||
        MediaQuery.maybeLetterSpacingOverrideOf(context) != null ||
        MediaQuery.maybeWordSpacingOverrideOf(context) != null) {
      return super.build(context);
    }
    return _TableLabel(
      cache: cache,
      spec: (
        text: data!,
        style: effectiveStyle,
        scaler: MediaQuery.textScalerOf(context),
        direction: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        align: textAlign ?? defaults.textAlign ?? TextAlign.start,
        lines: maxLines ?? defaults.maxLines,
        overflow: effectiveOverflow,
        wrap: softWrap ?? defaults.softWrap,
        heightBehavior:
            defaults.textHeightBehavior ??
            DefaultTextHeightBehavior.maybeOf(context),
        group: prefetchGroup,
      ),
    );
  }
}

class _TableLabel extends LeafRenderObjectWidget {
  const _TableLabel({required this.cache, required this.spec});
  final SongTableTextCache cache;
  final _TextSpec spec;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTableLabel(cache, spec);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTableLabel renderObject,
  ) => renderObject.update(cache, spec);
}

class _RenderTableLabel extends RenderBox {
  _RenderTableLabel(this._cache, this._spec);
  SongTableTextCache _cache;
  _TextSpec _spec;
  _TextLayout? _layout;

  void update(SongTableTextCache cache, _TextSpec spec) {
    if (_cache == cache && _spec == spec) return;
    if (attached && _cache != cache) {
      _cache.removeListener(markNeedsLayout);
      cache.addListener(markNeedsLayout);
    }
    _cache = cache;
    _spec = spec;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _cache.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _cache.removeListener(markNeedsLayout);
    super.detach();
  }

  T _measure<T>(BoxConstraints constraints, T Function(TextPainter) read) {
    final entry = _cache._acquire(_spec, constraints);
    try {
      return read(entry.painter);
    } finally {
      entry.release();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, (p) => constraints.constrain(p.size));
  @override
  double computeMinIntrinsicWidth(double height) =>
      _measure(const BoxConstraints(), (p) => p.minIntrinsicWidth);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _measure(const BoxConstraints(), (p) => p.maxIntrinsicWidth);
  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _layout?.painter.computeDistanceToActualBaseline(baseline);
  @override
  void performLayout() {
    final next = _cache._acquire(_spec, constraints);
    _layout?.release();
    _layout = next;
    size = constraints.constrain(next.painter.size);
    _cache._queueWarmup(_spec, constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;
  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _layout!.painter;
    void draw(PaintingContext context, Offset offset) =>
        painter.paint(context.canvas, offset);
    if (_spec.overflow != TextOverflow.visible &&
        (painter.didExceedMaxLines ||
            painter.width > size.width ||
            painter.height > size.height)) {
      context.canvas
        ..save()
        ..clipRect(offset & size);
      draw(context, offset);
      context.canvas.restore();
    } else {
      draw(context, offset);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _spec.text
      ..textDirection = _spec.direction;
  }

  @override
  void dispose() {
    _layout?.release();
    super.dispose();
  }
}
