import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';

class PlayBar extends StatelessWidget {
  final double height;
  const PlayBar({super.key, this.height = AetherSpace.playBarHeight});

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  IconData _playModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.shuffle:
        return Icons.shuffle;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.list:
        return Icons.repeat;
    }
  }

  String _playModeTooltip(PlayMode mode) {
    switch (mode) {
      case PlayMode.shuffle:
        return '随机播放';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.list:
        return '列表循环';
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;
    final playingSong = audioProvider.playingSong;

    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progress = totMs > 0 ? curMs / totMs : 0.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: cfg.bg1,
          border: Border(top: BorderSide(color: cfg.borderSubtle)),
        ),
        child: Stack(
          children: [
            // Top-edge seek bar: 1:1 drag, no decorative motion.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AetherSeekBar(
                progress: progress,
                height: 4,
                onSeek: (pct) {
                  final targetMs =
                      (audioProvider.totalDuration.inMilliseconds * pct)
                          .toInt();
                  audioProvider.seek(Duration(milliseconds: targetMs));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AetherSpace.xxxl,
                AetherSpace.md,
                AetherSpace.xxxl,
                0,
              ),
              child: Row(
                children: [
                  // Track info
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        AetherPressable(
                          enabled: playingSong != null,
                          borderRadius:
                              BorderRadius.circular(AetherRadius.md),
                          pressScale: AetherMotion.pressScale,
                          hoverColor: cfg.bgHover,
                          tooltip: playingSong == null
                              ? null
                              : (audioProvider.isDetailOpen
                                  ? '关闭详情'
                                  : '打开详情'),
                          onTap: playingSong == null
                              ? null
                              : () => audioProvider.setDetailOpen(
                                    !audioProvider.isDetailOpen,
                                  ),
                          child: AnimatedContainer(
                            duration: AetherMotion.duration(context, AetherMotion.fast),
                            curve: AetherMotion.out,
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AetherRadius.md),
                              color: playingSong != null
                                  ? cfg.accentMuted
                                  : cfg.bgHover,
                              border: Border.all(
                                color: audioProvider.isDetailOpen
                                    ? cfg.accent.withValues(alpha: 0.55)
                                    : cfg.borderSubtle,
                              ),
                            ),
                            child: Icon(
                              Icons.music_note,
                              color: playingSong != null
                                  ? cfg.accent
                                  : cfg.textTertiary,
                              size: AetherIconSize.xl,
                            ),
                          ),
                        ),
                        const SizedBox(width: AetherSpace.lg),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playingSong?.title ?? '暂无播放',
                                style: AetherType.bodyStyle(cfg.textPrimary)
                                    .copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AetherSpace.xxs),
                              Text(
                                playingSong?.artist ?? '…',
                                style:
                                    AetherType.captionStyle(cfg.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Transport
                  Expanded(
                    flex: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AetherIconButton(
                          icon: _playModeIcon(audioProvider.playMode),
                          onPressed: audioProvider.togglePlayMode,
                          size: 34,
                          iconSize: AetherIconSize.md,
                          color: audioProvider.playMode == PlayMode.list
                              ? cfg.textSecondary
                              : cfg.accent,
                          selected: audioProvider.playMode != PlayMode.list,
                          tooltip: _playModeTooltip(audioProvider.playMode),
                        ),
                        const SizedBox(width: AetherSpace.md),
                        AetherIconButton(
                          icon: Icons.skip_previous_rounded,
                          onPressed: audioProvider.playPrevious,
                          size: 38,
                          iconSize: AetherIconSize.xxl,
                          color: cfg.textPrimary,
                          tooltip: '上一首',
                        ),
                        const SizedBox(width: AetherSpace.md),
                        AetherPressable(
                          onTap: audioProvider.playPause,
                          borderRadius: BorderRadius.circular(AetherRadius.full),
                          pressScale: AetherMotion.pressScale,
                          tooltip:
                              audioProvider.isPlaying ? '暂停' : '播放',
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cfg.accent,
                              boxShadow: [
                                BoxShadow(
                                  color: cfg.accentGlow,
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            // Short crossfade only — state indication, not decoration.
                            child: AnimatedSwitcher(
                              duration: AetherMotion.duration(context, AetherMotion.press),
                              switchInCurve: AetherMotion.out,
                              switchOutCurve: AetherMotion.out,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: Icon(
                                audioProvider.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(audioProvider.isPlaying),
                                color: cfg.onAccent,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AetherSpace.md),
                        AetherIconButton(
                          icon: Icons.skip_next_rounded,
                          onPressed: audioProvider.playNext,
                          size: 38,
                          iconSize: AetherIconSize.xxl,
                          color: cfg.textPrimary,
                          tooltip: '下一首',
                        ),
                      ],
                    ),
                  ),

                  // Time + volume
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${_formatDuration(audioProvider.currentPosition)} / ${_formatDuration(audioProvider.totalDuration)}',
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                        const SizedBox(width: AetherSpace.lg),
                        Icon(
                          audioProvider.volume <= 0.001
                              ? Icons.volume_off_rounded
                              : audioProvider.volume < 0.4
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          size: AetherIconSize.md,
                          color: cfg.textSecondary,
                        ),
                        const SizedBox(width: AetherSpace.sm),
                        SizedBox(
                          width: 96,
                          height: 28,
                          child: AetherSlider(
                            value: audioProvider.volume,
                            onChanged: audioProvider.setVolume,
                            thumbRadius: 5,
                            trackHeight: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
