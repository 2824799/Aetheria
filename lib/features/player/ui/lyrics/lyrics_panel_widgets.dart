import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_shared.dart';
import 'package:aetheria/services/lyric_search_service.dart';
import 'package:aetheria/src/rust/models/song.dart';

// Building blocks shared by the lyric display tab and the lyric manager tab.

/// Which audio version the lyric belongs to and where the lyric came from,
/// with the tab's actions on the right.
class LyricPanelHeader extends StatelessWidget {
  const LyricPanelHeader({
    super.key,
    required this.audioVersion,
    required this.savedLyric,
    required this.actions,
  });

  final AudioVersion? audioVersion;
  final SavedLyric? savedLyric;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final lyric = savedLyric;
    final offset = lyric?.offsetMs ?? 0;
    final source = lyric == null
        ? '当前音源还没有保存歌词'
        : [
            lyricSourceLabel(lyric.source),
            if (offset != 0) '偏移 ${offset > 0 ? '+' : ''}$offset ms',
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.md,
        AetherSpace.md,
        AetherSpace.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  audioVersion?.originalName ?? '歌曲通用歌词',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.bodySmStyle(
                    cfg.textSecondary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.captionStyle(
                    cfg.textTertiary,
                  ).copyWith(fontSize: AetherType.bodySm - 1, height: 1.5),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// One-line problem report under the header.
class LyricPanelError extends StatelessWidget {
  const LyricPanelError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xl),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AetherType.bodySmStyle(context.tokens.warning),
      ),
    );
  }
}

/// "No lyrics yet" with the tab's primary action.
class LyricPanelEmptyState extends StatelessWidget {
  const LyricPanelEmptyState({
    super.key,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.loading = false,
  });

  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              color: cfg.textTertiary,
              size: AetherIconSize.hero,
            ),
            const SizedBox(height: AetherSpace.lg),
            Text('暂无歌词', style: AetherType.titleSmStyle(cfg.textPrimary)),
            const SizedBox(height: AetherSpace.xl),
            AetherButton.secondary(
              label: actionLabel,
              icon: actionIcon,
              loading: loading,
              onPressed: loading ? null : onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class LyricPanelLoading extends StatelessWidget {
  const LyricPanelLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: AetherProgress.circular(size: 16, strokeWidth: 2),
    );
  }
}

/// Search results; tap one to preview it before saving.
class LyricCandidateList extends StatelessWidget {
  const LyricCandidateList({
    super.key,
    required this.candidates,
    required this.height,
    required this.onSelected,
  });

  final List<LyricSearchCandidate> candidates;
  final double height;
  final ValueChanged<LyricSearchCandidate> onSelected;

  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(AetherRadius.md);
    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.sm,
        AetherSpace.xl,
        AetherSpace.md,
      ),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: cfg.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ListView.separated(
          itemCount: candidates.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: cfg.divider),
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            final duration = candidate.durationSec;
            final details = [
              candidate.sourceLabel,
              if (duration != null) _duration(duration),
              ?candidate.artist,
              ?candidate.album,
            ].join(' · ');
            return AetherPressable(
              onTap: () => onSelected(candidate),
              pressScale: 1,
              hoverColor: cfg.bgHover,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AetherSpace.lg,
                  AetherSpace.md,
                  AetherSpace.md,
                  AetherSpace.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidate.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AetherType.bodyStyle(
                              cfg.textPrimary,
                            ).copyWith(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AetherType.captionStyle(cfg.textTertiary)
                                .copyWith(
                                  fontSize: AetherType.bodySm - 1,
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: AetherIconSize.lg,
                      color: cfg.textTertiary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The saved lyric as selectable plain text.
class SavedLyricText extends StatelessWidget {
  const SavedLyricText({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final text = sanitizeLyricContent(content);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.md,
        AetherSpace.xl,
        AetherSpace.xl,
      ),
      child: SelectionArea(
        child: Text(
          text.isEmpty ? '没有可预览的内容' : text,
          style: AetherType.bodyStyle(
            text.isEmpty ? cfg.textTertiary : cfg.textSecondary,
          ).copyWith(height: 1.7),
        ),
      ),
    );
  }
}

/// Shifts lyric timing: step buttons, the value (tap to type one) and reset.
class LyricOffsetBar extends StatelessWidget {
  const LyricOffsetBar({
    super.key,
    required this.offsetMs,
    required this.enabled,
    required this.onChanged,
    required this.onEdit,
  });

  static const int _stepMs = 500;

  final int offsetMs;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final textColor = enabled ? cfg.textPrimary : cfg.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.xl,
        vertical: AetherSpace.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cfg.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('时间偏移', style: AetherType.bodySmStyle(cfg.textSecondary)),
          const Spacer(),
          AetherIconButton(
            icon: Icons.remove_rounded,
            size: 30,
            iconSize: AetherIconSize.md,
            tooltip: '提前 $_stepMs ms',
            onPressed: enabled ? () => onChanged(offsetMs - _stepMs) : null,
          ),
          AetherPressable(
            onTap: enabled ? onEdit : null,
            borderRadius: BorderRadius.circular(AetherRadius.sm),
            tooltip: enabled ? '输入偏移值' : null,
            child: Container(
              width: 84,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AetherRadius.sm),
                border: Border.all(color: cfg.borderSubtle),
              ),
              child: Text(
                '${offsetMs > 0 ? '+' : ''}$offsetMs ms',
                style: AetherType.bodySmStyle(textColor).copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          AetherIconButton(
            icon: Icons.add_rounded,
            size: 30,
            iconSize: AetherIconSize.md,
            tooltip: '延后 $_stepMs ms',
            onPressed: enabled ? () => onChanged(offsetMs + _stepMs) : null,
          ),
          const SizedBox(width: AetherSpace.xs),
          AetherButton.ghost(
            label: '重置',
            size: AetherButtonSize.sm,
            onPressed: enabled && offsetMs != 0 ? () => onChanged(0) : null,
          ),
        ],
      ),
    );
  }
}
