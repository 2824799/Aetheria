import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_quality.dart';
import 'package:aetheria/features/library/ui/song_table/song_columns.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_widgets.dart';
import 'package:aetheria/src/rust/models/song.dart';

class SongTableCellBuilder {
  const SongTableCellBuilder({
    required this.columnWidths,
    required this.columnOrder,
    required this.onResize,
    required this.onReorder,
    this.headerHeight = 40,
  });

  final Map<SongColumnKey, double> columnWidths;
  final List<SongColumnKey> columnOrder;
  final void Function(SongColumnKey column, double delta) onResize;
  final void Function(SongColumnKey dragged, SongColumnKey target) onReorder;
  final double headerHeight;

  Widget buildHeaderCell(SongColumnKey column, AppThemeConfig cfg) {
    final width = columnWidths[column] ?? column.defaultWidth;
    return SizedBox(
      width: width,
      height: headerHeight,
      child: DragTarget<SongColumnKey>(
        onWillAcceptWithDetails: (details) => details.data != column,
        onAcceptWithDetails: (details) => onReorder(details.data, column),
        builder: (context, candidateData, rejectedData) {
          final isDropTarget = candidateData.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: isDropTarget
                  ? cfg.bgHover.withValues(alpha: 0.08)
                  : cfg.bgHover.withValues(alpha: 0.35),
              border: Border(
                right: BorderSide(color: cfg.borderSubtle.withValues(alpha: 0.45)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Draggable<SongColumnKey>(
                    data: column,
                    feedback: Material(
                      color: cfg.bgHover.withValues(alpha: 0.35),
                      child: Container(
                        width: width,
                        height: headerHeight - 8,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cfg.bgPanel.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(AetherRadius.md),
                          border: Border.all(
                            color: cfg.accent.withValues(alpha: 0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cfg.scrim.withValues(alpha: 0.22),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          column.label,
                          style: TextStyle(
                            color: cfg.textPrimary,
                            fontSize: AetherType.titleSm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: buildHeaderLabel(column, cfg),
                    ),
                    child: buildHeaderLabel(column, cfg),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) =>
                        onResize(column, details.delta.dx),
                    child: Container(
                      width: 12,
                      alignment: Alignment.center,
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(
                          color: cfg.borderSubtle.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AetherRadius.full),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildHeaderLabel(SongColumnKey column, AppThemeConfig cfg) {
    final centered =
        column == SongColumnKey.versions || column == SongColumnKey.spec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Text(
        column.label,
        textAlign: centered ? TextAlign.center : TextAlign.left,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: cfg.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: AetherType.titleSm,
        ),
      ),
    );
  }


  Widget buildCell(
    SongColumnKey column,
    Song song,
    AudioVersion? primaryVersion,
    AppThemeConfig cfg,
    bool isCurrentlyPlaying,
    bool hasLyrics,
  ) {
    final width = columnWidths[column] ?? column.defaultWidth;

    switch (column) {
      case SongColumnKey.title:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrentlyPlaying ? cfg.accent : cfg.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: AetherType.titleSm,
                    ),
                  ),
                ),
                if (hasLyrics) ...[
                  const SizedBox(width: 6),
                  SongTableLrcBadge(cfg: cfg),
                ],
              ],
            ),
          ),
        );
      case SongColumnKey.artist:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              song.artist ?? '未知歌手',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cfg.textSecondary, fontSize: AetherType.body),
            ),
          ),
        );
      case SongColumnKey.tags:
        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: song.tags.isEmpty
                ? Text(
                    '无标签',
                    style: TextStyle(
                      color: cfg.textSecondary.withValues(alpha: 0.75),
                      fontSize: AetherType.bodySm,
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: song.tags.map((tag) {
                        final tagColor = tag.color != null
                            ? songTableParseHexColor(tag.color!, cfg.accent)
                            : cfg.accent;
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AetherRadius.xs),
                            border: Border(
                              left: BorderSide(color: tagColor, width: 2),
                            ),
                          ),
                          child: Text(
                            tag.name,
                            style: TextStyle(
                              fontSize: AetherType.caption,
                              color: tagColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        );
      case SongColumnKey.versions:
        return SizedBox(
          width: width,
          child: Center(
            child: Text(
              song.versions.length.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cfg.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: AetherType.body,
              ),
            ),
          ),
        );
      case SongColumnKey.spec:
        final specText = audioQualityText(primaryVersion);
        final badgeColor = audioQualityColor(primaryVersion, cfg.textSecondary);

        return SizedBox(
          width: width,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AetherRadius.xs),
              ),
              child: Text(
                specText,
                style: TextStyle(
                  fontSize: AetherType.caption,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
          ),
        );
    }
  }


}
