import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/player/version_actions.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// The audio versions of [song] with their actions, plus a button to add one.
/// Shared by the desktop detail pane and the mobile detail sheet.
class SongVersionList extends StatelessWidget {
  const SongVersionList({super.key, required this.song, this.header});

  final Song song;

  /// Optional widget scrolled together with the list, above the versions.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final canDelete = song.versions.length > 1;
    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AetherSpace.xl,
              AetherSpace.md,
              AetherSpace.xl,
              AetherSpace.md,
            ),
            children: [
              ?header,
              for (final version in song.versions)
                Padding(
                  padding: const EdgeInsets.only(bottom: AetherSpace.md),
                  child: _VersionCard(
                    song: song,
                    version: version,
                    canDelete: canDelete,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AetherSpace.xl,
            AetherSpace.xs,
            AetherSpace.xl,
            AetherSpace.xl,
          ),
          child: AetherButton.secondary(
            label: '添加音源版本',
            icon: Icons.add_rounded,
            expanded: true,
            onPressed: () => linkNewVersion(context, song),
          ),
        ),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.song,
    required this.version,
    required this.canDelete,
  });

  final Song song;
  final AudioVersion version;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final loudness = version.loudness;
    final isPrimary = version.isPrimary;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.lg,
        AetherSpace.md,
        AetherSpace.sm,
        AetherSpace.md,
      ),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(AetherRadius.md),
        border: Border.all(
          color: isPrimary ? cfg.borderFocus : cfg.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  version.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.bodyStyle(
                    cfg.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AetherIconButton.dense(
                icon: Icons.file_download_outlined,
                color: cfg.textSecondary,
                tooltip: '导出文件',
                onPressed: () => exportVersion(context, version),
              ),
              if (canDelete)
                AetherIconButton.dense(
                  icon: Icons.delete_outline_rounded,
                  color: cfg.danger,
                  tooltip: '删除版本',
                  onPressed: () => deleteVersion(context, version),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AetherSpace.sm),
            child: Text(
              [
                formatVersionSpecs(version),
                if (loudness != null) '${loudness.toStringAsFixed(1)} LUFS',
                if (!version.metadataScanned) '待完整扫描',
              ].join(' · '),
              style: AetherType.captionStyle(
                cfg.textTertiary,
              ).copyWith(fontSize: AetherType.bodySm - 1, height: 1.5),
            ),
          ),
          const SizedBox(height: AetherSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AetherPressable(
              onTap: isPrimary
                  ? null
                  : () => makeVersionPrimary(context, song, version),
              borderRadius: BorderRadius.circular(AetherRadius.sm),
              tooltip: isPrimary
                  ? '播放这首歌时优先使用这个版本'
                  : '改用这个版本播放；若正在播放，会按当前进度切换',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPrimary
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: AetherIconSize.md,
                      color: isPrimary ? cfg.accent : cfg.textTertiary,
                    ),
                    const SizedBox(width: AetherSpace.sm),
                    Text(
                      isPrimary ? '默认播放版本' : '设为默认播放版本',
                      style: AetherType.bodySmStyle(
                        isPrimary ? cfg.textPrimary : cfg.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
