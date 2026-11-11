import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_cells.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_selection.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// One song row.
///
/// Rebuilds only when this song's own playback state changes; selection is
/// repainted through [SongTableSelection.changes] without rebuilding cells.
class SongTableRow extends StatelessWidget {
  const SongTableRow({
    super.key,
    required this.song,
    required this.width,
    required this.height,
    required this.leadingWidth,
    required this.hasLyrics,
    required this.cells,
    required this.selection,
    required this.onTap,
    required this.onPlayPressed,
    required this.onContextMenu,
  });

  final Song song;
  final double width;
  final double height;
  final double leadingWidth;
  final bool hasLyrics;
  final SongTableCells cells;
  final SongTableSelection selection;
  final VoidCallback onTap;

  /// Called with whether this row is the song loaded in the player.
  final ValueChanged<bool> onPlayPressed;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final songId = song.id;

    return Selector<
      AudioPlayerProvider,
      ({bool loaded, bool active, bool running})
    >(
      selector: (_, audio) {
        final loaded = audio.playingSong?.id == songId;
        return (
          loaded: loaded,
          active: audio.activeSong?.id == songId,
          running: loaded && audio.isPlaying,
        );
      },
      builder: (context, state, _) {
        return SizedBox(
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) =>
                onContextMenu(details.globalPosition),
            child: AetherPressable(
              pressScale: 1,
              hoverColor: cfg.bgHover,
              onTap: onTap,
              child: AnimatedBuilder(
                animation: selection.changes,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: selection.contains(songId)
                        ? cfg.selection
                        : state.active
                        ? cfg.accentMuted
                        : null,
                  ),
                  position: DecorationPosition.background,
                  child: child,
                ),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: cfg.divider),
                      left: BorderSide(
                        color: state.active ? cfg.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: leadingWidth,
                        child: AetherIconButton(
                          icon: state.running
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          iconSize: AetherIconSize.xl,
                          size: 32,
                          color: state.loaded ? cfg.accent : cfg.textTertiary,
                          tooltip: state.running ? '暂停' : '播放',
                          onPressed: () => onPlayPressed(state.loaded),
                        ),
                      ),
                      for (final column in cells.layout.order)
                        cells.build(
                          column,
                          song,
                          cfg,
                          isPlaying: state.loaded,
                          hasLyrics: hasLyrics,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
