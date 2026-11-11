import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Every library tag, grouped by category; tap one to bind or unbind it from
/// [song]. Shared by the desktop detail pane and the mobile detail sheet.
class SongTagEditor extends StatelessWidget {
  const SongTagEditor({super.key, required this.song});

  final Song song;

  static const String _uncategorized = '自定义';

  Future<void> _toggle(BuildContext context, Tag tag, bool bind) async {
    try {
      await context.read<LibraryProvider>().tagSong(song.id, tag.id, bind);
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '修改标签失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final tags = context.select<LibraryProvider, List<Tag>>(
      (library) => library.tags,
    );
    if (tags.isEmpty) {
      return const AetherEmptyState(
        icon: Icons.sell_outlined,
        title: '还没有标签',
        message: '先在“管理标签”中新建标签，再回到这里为歌曲打标签',
      );
    }

    // Insertion order keeps categories in the order the library lists them.
    final groups = <String, List<Tag>>{};
    for (final tag in tags) {
      groups.putIfAbsent(tag.category ?? _uncategorized, () => []).add(tag);
    }
    final boundIds = {for (final tag in song.tags) tag.id};

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.md,
        AetherSpace.xl,
        AetherSpace.xl,
      ),
      children: [
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AetherSpace.md,
              bottom: AetherSpace.md,
            ),
            child: Text(
              group.key,
              style: AetherType.labelStyle(cfg.textTertiary),
            ),
          ),
          Wrap(
            spacing: AetherSpace.md,
            runSpacing: AetherSpace.md,
            children: [
              for (final tag in group.value)
                _TagToggle(
                  tag: tag,
                  bound: boundIds.contains(tag.id),
                  onTap: () =>
                      _toggle(context, tag, !boundIds.contains(tag.id)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TagToggle extends StatelessWidget {
  const _TagToggle({
    required this.tag,
    required this.bound,
    required this.onTap,
  });

  final Tag tag;
  final bool bound;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final color = parseTagColor(tag.color, cfg.textSecondary);
    final radius = BorderRadius.circular(AetherRadius.full);

    return AetherPressable(
      onTap: onTap,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: bound ? null : cfg.bgHover,
      semanticLabel: bound ? '移除标签 ${tag.name}' : '添加标签 ${tag.name}',
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.out,
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.lg,
          vertical: AetherSpace.sm,
        ),
        decoration: BoxDecoration(
          color: bound ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: radius,
          border: Border.all(
            color: bound ? color.withValues(alpha: 0.7) : cfg.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bound)
              Icon(Icons.check_rounded, size: AetherIconSize.sm, color: color)
            else
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3.5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: AetherSpace.sm),
            Text(
              tag.name,
              style: AetherType.bodySmStyle(
                bound ? cfg.textPrimary : cfg.textSecondary,
              ).copyWith(fontWeight: bound ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}
