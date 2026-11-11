import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/song_table/song_columns.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_column_layout.dart';

/// Column titles. Drag a title to reorder, drag its right edge to resize.
class SongTableHeader extends StatelessWidget {
  const SongTableHeader({
    super.key,
    required this.layout,
    required this.height,
    required this.leadingWidth,
  });

  final SongTableColumnLayout layout;
  final double height;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cfg.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(width: leadingWidth),
          for (final column in layout.order)
            _HeaderCell(column: column, layout: layout, height: height),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.layout,
    required this.height,
  });

  final SongColumnKey column;
  final SongTableColumnLayout layout;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final width = layout.widthOf(column);
    final label = _HeaderLabel(column: column);

    return SizedBox(
      width: width,
      height: height,
      child: DragTarget<SongColumnKey>(
        onWillAcceptWithDetails: (details) => details.data != column,
        onAcceptWithDetails: (details) => layout.reorder(details.data, column),
        builder: (context, candidates, _) => ColoredBox(
          color: candidates.isEmpty ? Colors.transparent : cfg.selection,
          child: Row(
            children: [
              Expanded(
                child: Draggable<SongColumnKey>(
                  data: column,
                  feedback: _DragFeedback(
                    column: column,
                    width: width,
                    height: height - AetherSpace.md,
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: label),
                  child: label,
                ),
              ),
              _ResizeHandle(column: column, layout: layout),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel({required this.column});

  final SongColumnKey column;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
      alignment: column.isCentered ? Alignment.center : Alignment.centerLeft,
      child: Text(
        column.label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: AetherType.labelStyle(cfg.textTertiary),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.column, required this.layout});

  final SongColumnKey column;
  final SongTableColumnLayout layout;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  void _endDrag() {
    setState(() => _dragging = false);
    widget.layout.save();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) =>
            widget.layout.resize(widget.column, details.delta.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          width: AetherSpace.lg,
          child: Center(
            child: Container(
              width: active ? 2 : 1,
              height: 16,
              decoration: BoxDecoration(
                color: active ? cfg.accent : cfg.borderStrong,
                borderRadius: BorderRadius.circular(AetherRadius.full),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({
    required this.column,
    required this.width,
    required this.height,
  });

  final SongColumnKey column;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
        decoration: BoxDecoration(
          color: cfg.bgPopover,
          borderRadius: BorderRadius.circular(AetherRadius.md),
          border: Border.all(color: cfg.borderFocus),
          boxShadow: [
            BoxShadow(
              color: cfg.scrim.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(column.label, style: AetherType.labelStyle(cfg.textPrimary)),
      ),
    );
  }
}
