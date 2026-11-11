import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:aetheria/core/theme/tokens/motion.dart';

/// Where one mounted list item sits: its index, the scroll offset that would
/// centre it, and its height.
typedef MobileSongScrollSample = ({
  int index,
  double centeredOffset,
  double extent,
});

/// Estimates the scroll offset that centres item [targetIndex] in a list of
/// variable-height items, extrapolating from the items currently mounted.
/// Without samples it falls back to the item's fraction of the scroll range.
double estimateMobileSongScrollOffset({
  required int targetIndex,
  required int itemCount,
  required List<MobileSongScrollSample> samples,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  if (itemCount <= 1 || maxScrollExtent <= minScrollExtent) {
    return minScrollExtent;
  }

  if (samples.isEmpty) {
    final fraction = targetIndex.clamp(0, itemCount - 1) / (itemCount - 1);
    return minScrollExtent + (maxScrollExtent - minScrollExtent) * fraction;
  }

  final ordered = List<MobileSongScrollSample>.of(samples)
    ..sort((a, b) => a.index.compareTo(b.index));
  final anchor = ordered.reduce(
    (best, sample) =>
        (sample.index - targetIndex).abs() < (best.index - targetIndex).abs()
        ? sample
        : best,
  );

  var estimatedExtent =
      ordered.map((sample) => sample.extent).reduce((a, b) => a + b) /
      ordered.length;
  final first = ordered.first;
  final last = ordered.last;
  if (last.index != first.index) {
    // The distance between two mounted items includes their spacing, which
    // the items' own heights do not.
    final measuredExtent =
        (last.centeredOffset - first.centeredOffset) /
        (last.index - first.index);
    if (measuredExtent.isFinite && measuredExtent > 0) {
      estimatedExtent = measuredExtent;
    }
  }

  return (anchor.centeredOffset +
          (targetIndex - anchor.index) * estimatedExtent)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}

enum MobileSongRevealResult {
  revealed,

  /// The scroll could not land on the song after several attempts.
  unreachable,

  /// Nothing was done: another reveal is running or the list went away.
  cancelled,
}

/// Scrolls a lazily built, variable-height song list to a given song.
///
/// List items register themselves through [MobileSongAnchor]. A song that is
/// not mounted is approached by estimating its offset from the mounted ones
/// and correcting until it gets built.
class MobileSongRevealer {
  MobileSongRevealer(this.scrollController);

  static const int _maxAttempts = 4;

  final ScrollController scrollController;
  final Map<String, BuildContext> _anchors = <String, BuildContext>{};
  bool _busy = false;

  void _mount(String songId, BuildContext anchor) => _anchors[songId] = anchor;

  void _unmount(String songId, BuildContext anchor) {
    if (identical(_anchors[songId], anchor)) {
      _anchors.remove(songId);
    }
  }

  /// Centres the song at [targetIndex] of [songIds]. [context] is the list's
  /// owner; the reveal stops when it is unmounted.
  Future<MobileSongRevealResult> reveal(
    BuildContext context,
    List<String> songIds,
    int targetIndex,
  ) async {
    if (_busy) return MobileSongRevealResult.cancelled;
    _busy = true;
    try {
      final songId = songIds[targetIndex];
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted || !scrollController.hasClients) {
        return MobileSongRevealResult.cancelled;
      }
      if (await _centerMounted(context, songId)) {
        return MobileSongRevealResult.revealed;
      }

      final indexById = <String, int>{
        for (var index = 0; index < songIds.length; index++)
          songIds[index]: index,
      };
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        if (!context.mounted || !scrollController.hasClients) {
          return MobileSongRevealResult.cancelled;
        }
        final position = scrollController.position;
        final target = estimateMobileSongScrollOffset(
          targetIndex: targetIndex,
          itemCount: songIds.length,
          samples: _samples(indexById),
          minScrollExtent: position.minScrollExtent,
          maxScrollExtent: position.maxScrollExtent,
        );

        if ((position.pixels - target).abs() >= 0.5) {
          if (AetherMotion.reduce(context)) {
            scrollController.jumpTo(target);
          } else {
            await scrollController.animateTo(
              target,
              duration: attempt == 0 ? AetherMotion.slow : AetherMotion.normal,
              curve: AetherMotion.outQuart,
            );
          }
        }

        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return MobileSongRevealResult.cancelled;
        if (await _centerMounted(context, songId)) {
          return MobileSongRevealResult.revealed;
        }
      }
      return MobileSongRevealResult.unreachable;
    } finally {
      _busy = false;
    }
  }

  Future<bool> _centerMounted(BuildContext context, String songId) async {
    final anchor = _anchors[songId];
    final renderObject = anchor?.findRenderObject();
    if (anchor == null || renderObject == null || !renderObject.attached) {
      return false;
    }
    await Scrollable.ensureVisible(
      anchor,
      alignment: 0.5,
      duration: AetherMotion.duration(context, AetherMotion.slow),
      curve: AetherMotion.outQuart,
    );
    return context.mounted;
  }

  List<MobileSongScrollSample> _samples(Map<String, int> indexById) {
    final samples = <MobileSongScrollSample>[];
    for (final entry in _anchors.entries) {
      final index = indexById[entry.key];
      final renderObject = entry.value.findRenderObject();
      if (index == null ||
          renderObject is! RenderBox ||
          !renderObject.attached) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;
      samples.add((
        index: index,
        centeredOffset: viewport.getOffsetToReveal(renderObject, 0.5).offset,
        extent: renderObject.size.height,
      ));
    }
    return samples;
  }
}

/// Registers a list item with [revealer] while it is mounted.
class MobileSongAnchor extends StatefulWidget {
  const MobileSongAnchor({
    super.key,
    required this.songId,
    required this.revealer,
    required this.child,
  });

  final String songId;
  final MobileSongRevealer revealer;
  final Widget child;

  @override
  State<MobileSongAnchor> createState() => _MobileSongAnchorState();
}

class _MobileSongAnchorState extends State<MobileSongAnchor> {
  @override
  void didUpdateWidget(covariant MobileSongAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        oldWidget.revealer != widget.revealer) {
      oldWidget.revealer._unmount(oldWidget.songId, context);
    }
  }

  @override
  void dispose() {
    widget.revealer._unmount(widget.songId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.revealer._mount(widget.songId, context);
    return widget.child;
  }
}
