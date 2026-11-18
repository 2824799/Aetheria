import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_choice_group.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/phigros/phigros_badges.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Per-song Phigros difficulty switcher, chart breakdown, and hitsound controls.
class PhigrosDetailPanel extends StatelessWidget {
  const PhigrosDetailPanel({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final phigros = song.phigros;
    if (phigros == null) {
      return const SizedBox.shrink();
    }
    final cfg = context.tokens;
    final library = context.read<LibraryProvider>();
    final audio = context.watch<AudioPlayerProvider>();
    final activeChart = AudioPlayerProvider.activePhigrosChartFor(phigros);
    final effective = audio.resolveHitsoundForSong(song);

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(AetherSpace.xl),
        children: [
          _SongMetadataCard(phigros: phigros, activeChart: activeChart, cfg: cfg),
          const SizedBox(height: AetherSpace.lg),
          _DifficultySelectorCard(
            song: song,
            phigros: phigros,
            activeChart: activeChart,
            cfg: cfg,
            onSelect: (diff) => _selectDifficulty(context, library, diff),
          ),
          const SizedBox(height: AetherSpace.lg),
          SelectionContainer.disabled(
            child: _PerSongHitsoundCard(
              song: song,
              phigros: phigros,
              globalEnabled: audio.phigrosHitsoundEnabled,
              globalVolume: audio.phigrosHitsoundVolume,
              globalOffsetMs: audio.phigrosHitsoundOffsetMs,
              effectiveEnabled: effective.enabled,
              effectiveVolume: effective.volume,
              effectiveOffsetMs: effective.offsetMs,
              cfg: cfg,
              onUpdate: ({required mode, volume, offsetMs}) => _updateHitsound(
                context,
                library,
                mode: mode,
                volume: volume,
                offsetMs: offsetMs,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDifficulty(
    BuildContext context,
    LibraryProvider library,
    String difficulty,
  ) async {
    try {
      await changePhigrosDifficultyAndSync(context, library, song, difficulty);
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '切换难度失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _updateHitsound(
    BuildContext context,
    LibraryProvider library, {
    required String mode,
    double? volume,
    int? offsetMs,
  }) async {
    try {
      await updatePhigrosSongHitsoundAndSync(
        context,
        library,
        song,
        mode: mode,
        volume: volume,
        offsetMs: offsetMs,
      );
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '保存打击音效设置失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }
}

class _SongMetadataCard extends StatelessWidget {
  const _SongMetadataCard({
    required this.phigros,
    required this.activeChart,
    required this.cfg,
  });

  final PhigrosSongMeta phigros;
  final PhigrosChartMeta? activeChart;
  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    final chart = activeChart;
    return AetherSurface(
      level: AetherSurfaceLevel.panel,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: const EdgeInsets.all(AetherSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_esports_rounded, size: AetherIconSize.md, color: cfg.accent),
              const SizedBox(width: AetherSpace.sm),
              Expanded(
                child: Text(
                  phigros.chapter,
                  style: AetherType.labelStyle(cfg.accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (chart?.audioRelPath != null)
                Padding(
                  padding: const EdgeInsets.only(left: AetherSpace.sm),
                  child: Text(
                    '差异音源',
                    style: AetherType.captionStyle(cfg.info),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AetherSpace.md),
          _MetaLine(label: '曲师', value: phigros.composer, cfg: cfg),
          if (phigros.illustrator.isNotEmpty) ...[
            const SizedBox(height: AetherSpace.xs),
            _MetaLine(label: '画师', value: phigros.illustrator, cfg: cfg),
          ],
          if (chart != null && chart.charter.isNotEmpty) ...[
            const SizedBox(height: AetherSpace.xs),
            _MetaLine(label: '谱师', value: chart.charter, cfg: cfg),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
    required this.cfg,
  });

  final String label;
  final String value;
  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: AetherType.captionStyle(cfg.textTertiary)),
        ),
        Expanded(
          child: Text(
            value,
            style: AetherType.bodySmStyle(cfg.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _DifficultySelectorCard extends StatelessWidget {
  const _DifficultySelectorCard({
    required this.song,
    required this.phigros,
    required this.activeChart,
    required this.cfg,
    required this.onSelect,
  });

  final Song song;
  final PhigrosSongMeta phigros;
  final PhigrosChartMeta? activeChart;
  final AppThemeConfig cfg;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return AetherSurface(
      level: AetherSurfaceLevel.panel,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: const EdgeInsets.all(AetherSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('谱面难度切换', style: AetherType.labelStyle(cfg.textPrimary)),
              const Spacer(),
              Text(
                '播放中可实时切换',
                style: AetherType.captionStyle(cfg.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AetherSpace.md),
          SelectionContainer.disabled(
            child: Wrap(
              spacing: AetherSpace.sm,
              runSpacing: AetherSpace.sm,
              children: [
                for (final chart in phigros.charts)
                  _DifficultyChip(
                    chart: chart,
                    selected: chart.difficulty == phigros.selectedDifficulty,
                    cfg: cfg,
                    onTap: () => onSelect(chart.difficulty),
                  ),
              ],
            ),
          ),
          if (activeChart != null) ...[
            const SizedBox(height: AetherSpace.lg),
            Divider(height: 1, color: cfg.divider),
            const SizedBox(height: AetherSpace.md),
            Wrap(
              spacing: AetherSpace.xl,
              runSpacing: AetherSpace.sm,
              children: [
                _StatItem(
                  label: 'BPM',
                  value: formatPhigrosBpm(
                    activeChart!.bpmMin,
                    activeChart!.bpmMax,
                  ),
                  cfg: cfg,
                ),
                _StatItem(
                  label: '谱面偏移',
                  value: '${activeChart!.chartOffsetMs} ms',
                  cfg: cfg,
                ),
                _StatItem(
                  label: '总物量',
                  value: '${activeChart!.noteCount}',
                  cfg: cfg,
                ),
              ],
            ),
            const SizedBox(height: AetherSpace.md),
            Wrap(
              spacing: AetherSpace.md,
              runSpacing: AetherSpace.xs,
              children: [
                _NotePill(
                  label: 'Tap',
                  count: activeChart!.tapCount,
                  color: cfg.info,
                ),
                _NotePill(
                  label: 'Drag',
                  count: activeChart!.dragCount,
                  color: cfg.warning,
                ),
                _NotePill(
                  label: 'Hold',
                  count: activeChart!.holdCount,
                  color: cfg.accent,
                ),
                _NotePill(
                  label: 'Flick',
                  count: activeChart!.flickCount,
                  color: cfg.danger,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({
    required this.chart,
    required this.selected,
    required this.cfg,
    required this.onTap,
  });

  final PhigrosChartMeta chart;
  final bool selected;
  final AppThemeConfig cfg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = phigrosDifficultyColor(chart.difficulty, cfg);
    final radius = BorderRadius.circular(AetherRadius.md);
    final diffName = chart.difficulty.replaceAll('_Error', ' · Err');
    final rating = formatPhigrosRating(chart.rating);

    return AetherPressable(
      onTap: onTap,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.lg,
          vertical: AetherSpace.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : cfg.bgHover,
          borderRadius: radius,
          border: Border.all(
            color: selected ? color : cfg.borderSubtle,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              diffName,
              style: AetherType.captionStyle(
                selected ? color : cfg.textSecondary,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Lv.$rating',
              style: AetherType.bodySmStyle(
                selected ? cfg.textPrimary : cfg.textSecondary,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.cfg,
  });

  final String label;
  final String value;
  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AetherType.captionStyle(cfg.textTertiary)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AetherType.bodySmStyle(cfg.textPrimary).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NotePill extends StatelessWidget {
  const _NotePill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AetherRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label $count',
        style: AetherType.captionStyle(color).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

typedef _PerSongHitsoundCallback = Future<void> Function({
  required String mode,
  double? volume,
  int? offsetMs,
});

class _PerSongHitsoundCard extends StatelessWidget {
  const _PerSongHitsoundCard({
    required this.song,
    required this.phigros,
    required this.globalEnabled,
    required this.globalVolume,
    required this.globalOffsetMs,
    required this.effectiveEnabled,
    required this.effectiveVolume,
    required this.effectiveOffsetMs,
    required this.cfg,
    required this.onUpdate,
  });

  final Song song;
  final PhigrosSongMeta phigros;
  final bool globalEnabled;
  final double globalVolume;
  final int globalOffsetMs;
  final bool effectiveEnabled;
  final double effectiveVolume;
  final int effectiveOffsetMs;
  final AppThemeConfig cfg;
  final _PerSongHitsoundCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final hasCustomVolume = phigros.hitsoundVolume != null;
    final hasCustomOffset = phigros.hitsoundOffsetMs != null;
    final hasAnyOverride =
        phigros.hitsoundMode != 'global' || hasCustomVolume || hasCustomOffset;

    final shownVolume = (phigros.hitsoundVolume ?? globalVolume).clamp(0.0, 1.5);
    final shownOffset = (phigros.hitsoundOffsetMs ?? globalOffsetMs).clamp(-300, 300);

    return AetherSurface(
      level: AetherSurfaceLevel.panel,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: const EdgeInsets.all(AetherSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('单曲打击音效调节', style: AetherType.labelStyle(cfg.textPrimary)),
              ),
              if (hasAnyOverride)
                AetherButton.ghost(
                  label: '全部恢复全局',
                  size: AetherButtonSize.sm,
                  onPressed: () => onUpdate(
                    mode: 'global',
                    volume: null,
                    offsetMs: null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AetherSpace.md),
          AetherChoiceGroup<String>(
            value: phigros.hitsoundMode,
            onChanged: (mode) => onUpdate(
              mode: mode,
              volume: phigros.hitsoundVolume,
              offsetMs: phigros.hitsoundOffsetMs,
            ),
            options: [
              AetherChoiceOption(
                value: 'global',
                label: globalEnabled ? '跟随全局(开)' : '跟随全局(关)',
              ),
              const AetherChoiceOption(value: 'on', label: '单独开启'),
              const AetherChoiceOption(value: 'off', label: '单独关闭'),
            ],
          ),
          const SizedBox(height: AetherSpace.lg),
          Row(
            children: [
              Text('打击音量', style: AetherType.bodySmStyle(cfg.textPrimary)),
              const SizedBox(width: AetherSpace.sm),
              Text(
                hasCustomVolume
                    ? '独立 ${(shownVolume * 100).round()}%'
                    : '全局 ${(globalVolume * 100).round()}%',
                style: AetherType.captionStyle(
                  hasCustomVolume ? cfg.accent : cfg.textTertiary,
                ),
              ),
              const Spacer(),
              if (hasCustomVolume)
                AetherIconButton.dense(
                  icon: Icons.restart_alt_rounded,
                  tooltip: '音量恢复跟随全局',
                  onPressed: () => onUpdate(
                    mode: phigros.hitsoundMode,
                    volume: null,
                    offsetMs: phigros.hitsoundOffsetMs,
                  ),
                ),
            ],
          ),
          AetherSlider(
            value: shownVolume,
            min: 0.0,
            max: 1.5,
            divisions: 30,
            onChanged: (val) => onUpdate(
              mode: phigros.hitsoundMode,
              volume: val,
              offsetMs: phigros.hitsoundOffsetMs,
            ),
          ),
          const SizedBox(height: AetherSpace.md),
          Row(
            children: [
              Text('延迟微调', style: AetherType.bodySmStyle(cfg.textPrimary)),
              const SizedBox(width: AetherSpace.sm),
              Text(
                hasCustomOffset
                    ? '独立 ${shownOffset >= 0 ? '+' : ''}$shownOffset ms'
                    : '全局 ${globalOffsetMs >= 0 ? '+' : ''}$globalOffsetMs ms',
                style: AetherType.captionStyle(
                  hasCustomOffset ? cfg.accent : cfg.textTertiary,
                ),
              ),
              const Spacer(),
              if (hasCustomOffset)
                AetherIconButton.dense(
                  icon: Icons.restart_alt_rounded,
                  tooltip: '偏移恢复跟随全局',
                  onPressed: () => onUpdate(
                    mode: phigros.hitsoundMode,
                    volume: phigros.hitsoundVolume,
                    offsetMs: null,
                  ),
                ),
            ],
          ),
          AetherSlider(
            value: shownOffset.toDouble(),
            min: -300,
            max: 300,
            divisions: 120,
            onChanged: (val) => onUpdate(
              mode: phigros.hitsoundMode,
              volume: phigros.hitsoundVolume,
              offsetMs: val.round(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final delta in const [-10, -1, 1, 10])
                AetherButton.secondary(
                  label: '${delta > 0 ? '+' : ''}$delta ms',
                  size: AetherButtonSize.sm,
                  onPressed: () => onUpdate(
                    mode: phigros.hitsoundMode,
                    volume: phigros.hitsoundVolume,
                    offsetMs: (shownOffset + delta).clamp(-300, 300),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AetherSpace.lg),
          Divider(height: 1, color: cfg.divider),
          const SizedBox(height: AetherSpace.md),
          Text(
            effectiveEnabled
                ? '当前生效：已启用打击音效 · 音量 ${(effectiveVolume * 100).round()}% · 偏移 ${effectiveOffsetMs >= 0 ? '+' : ''}$effectiveOffsetMs ms'
                : '当前生效：已静音打击音效',
            style: AetherType.captionStyle(
              effectiveEnabled ? cfg.textSecondary : cfg.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
