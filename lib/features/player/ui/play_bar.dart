import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';

class PlayBar extends StatelessWidget {
  final double height;
  const PlayBar({super.key, this.height = 90});

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _handleSeek(BuildContext context, double globalDx, AudioPlayerProvider provider) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    final width = box.size.width;
    if (width <= 0) return;
    
    final localX = box.globalToLocal(Offset(globalDx, 0)).dx;
    final pct = (localX / width).clamp(0.0, 1.0);
    final targetMs = (provider.totalDuration.inMilliseconds * pct).toInt();
    provider.seek(Duration(milliseconds: targetMs));
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;
    
    final playingSong = audioProvider.playingSong;
    
    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progress = totMs > 0 ? curMs / totMs : 0.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cfg.bgPanel,
        border: Border(top: BorderSide(color: cfg.border)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Borderless Top Edge Progress Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 4,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) => _handleSeek(context, details.globalPosition.dx, audioProvider),
                onTapDown: (details) => _handleSeek(context, details.globalPosition.dx, audioProvider),
                child: Stack(
                  children: [
                    Container(
                      color: cfg.sliderTrack,
                      width: double.infinity,
                      height: 4,
                    ),
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        color: cfg.accent,
                        height: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Main PlayBar Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Track Info (Click Cover to Toggle Drawer)
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.25,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          if (playingSong != null) {
                            audioProvider.setDetailOpen(!audioProvider.isDetailOpen);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: cfg.border),
                          ),
                          child: Icon(Icons.music_note, color: playingSong != null ? cfg.accent : cfg.textSub),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playingSong?.title ?? '暂无播放',
                              style: TextStyle(
                                fontWeight: FontWeight.bold, 
                                fontSize: 13,
                                color: cfg.textMain,
                                fontFamily: 'Outfit',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              playingSong?.artist ?? '...',
                              style: TextStyle(
                                color: cfg.textSub, 
                                fontSize: 11,
                                fontFamily: 'Outfit',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Playback controls (Shuffle, Repeat, Prev, Play/Pause, Next)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Play Mode Selector
                      IconButton(
                        icon: Icon(
                          audioProvider.playMode == PlayMode.shuffle
                              ? Icons.shuffle
                              : audioProvider.playMode == PlayMode.single
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                          size: 18,
                          color: cfg.textSub,
                        ),
                        onPressed: () => audioProvider.togglePlayMode(),
                      ),
                      const SizedBox(width: 16),
                      // Skip Previous
                      IconButton(
                        icon: Icon(Icons.skip_previous, size: 24, color: cfg.textMain),
                        onPressed: () => audioProvider.playPrevious(),
                      ),
                      const SizedBox(width: 12),
                      // Play / Pause Circle Action
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cfg.accent,
                          boxShadow: [
                            BoxShadow(
                              color: cfg.accentGlow,
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            audioProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => audioProvider.playPause(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Skip Next
                      IconButton(
                        icon: Icon(Icons.skip_next, size: 24, color: cfg.textMain),
                        onPressed: () => audioProvider.playNext(),
                      ),
                    ],
                  ),
                ),
                
                // Volume controls & position duration text
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.25,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${_formatDuration(audioProvider.currentPosition)} / ${_formatDuration(audioProvider.totalDuration)}',
                        style: TextStyle(fontSize: 11, color: cfg.textSub, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.volume_up, size: 16, color: cfg.textSub),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 80,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: cfg.accent,
                            inactiveTrackColor: cfg.sliderTrack,
                            thumbColor: cfg.accent,
                          ),
                          child: Slider(
                            value: audioProvider.volume,
                            onChanged: (val) => audioProvider.setVolume(val),
                          ),
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
    );
  }
}
