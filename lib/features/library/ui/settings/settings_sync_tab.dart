import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';

typedef SettingsSyncPullHandler = Future<void> Function(
  BuildContext context,
  AppThemeConfig cfg,
  SyncDevice device,
  LibraryProvider libraryProvider,
  AudioPlayerProvider audioProvider,
  SyncProvider syncProvider,
);

class SettingsSyncTab extends StatelessWidget {
  const SettingsSyncTab({
    super.key,
    required this.cfg,
    required this.libraryProvider,
    required this.audioProvider,
    required this.syncProvider,
    required this.onPullDevice,
  });

  final AppThemeConfig cfg;
  final LibraryProvider libraryProvider;
  final AudioPlayerProvider audioProvider;
  final SyncProvider syncProvider;
  final SettingsSyncPullHandler onPullDevice;

  @override
  Widget build(BuildContext context) {
    final devices = syncProvider.devices;
    final request = syncProvider.incomingRequest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AetherSectionHeader(title: '局域网镜像同步'),
        AetherSurface(
          level: AetherSurfaceLevel.flat,
          color: cfg.bgHover,
          borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
          padding: const EdgeInsets.all(AetherSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    syncProvider.isRunning
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: AetherIconSize.md,
                    color: syncProvider.isRunning ? cfg.accent : cfg.textSecondary,
                  ),
                  const SizedBox(width: AetherSpace.md),
                  Expanded(
                    child: Text(
                      syncProvider.statusMessage,
                      style: AetherType.bodyStyle(cfg.textPrimary).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AetherSpace.md),
              Text(
                '本机名称：${syncProvider.localDeviceName}'
                '${syncProvider.localPort == null ? '' : ' · 端口 ${syncProvider.localPort}'}',
                style: AetherType.bodySmStyle(cfg.textSecondary),
              ),
              if (syncProvider.errorMessage != null) ...[
                const SizedBox(height: AetherSpace.md),
                Text(
                  syncProvider.errorMessage!,
                  style: AetherType.bodySmStyle(cfg.danger),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AetherSpace.lg),
        Wrap(
          spacing: AetherSpace.lg - 2,
          runSpacing: AetherSpace.lg - 2,
          children: [
            AetherButton.primary(
              label: syncProvider.isRunning ? '刷新发现设备' : '启动同步服务',
              icon: Icons.radar,
              size: AetherButtonSize.sm,
              onPressed: syncProvider.isRunning
                  ? () => syncProvider.announceNow()
                  : () => syncProvider.start(libraryProvider),
            ),
            AetherButton.secondary(
              label: '清空列表',
              icon: Icons.cleaning_services_outlined,
              size: AetherButtonSize.sm,
              onPressed: syncProvider.clearDevices,
            ),
          ],
        ),
        if (request != null) ...[
          const SizedBox(height: AetherSpace.lg + 2),
          AetherSurface(
            level: AetherSurfaceLevel.flat,
            color: cfg.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
            border: Border.all(color: cfg.warning.withValues(alpha: 0.35)),
            padding: const EdgeInsets.all(AetherSpace.lg),
            child: Row(
              children: [
                Icon(
                  Icons.notification_important_outlined,
                  size: AetherIconSize.lg,
                  color: cfg.warning,
                ),
                const SizedBox(width: AetherSpace.lg - 2),
                Expanded(
                  child: Text(
                    '${request.deviceName} 请求从本设备同步音乐库',
                    style: AetherType.bodyStyle(cfg.textPrimary),
                  ),
                ),
                AetherButton.ghost(
                  label: '拒绝',
                  size: AetherButtonSize.sm,
                  onPressed: () => syncProvider.denyIncomingRequest(request.id),
                ),
                const SizedBox(width: AetherSpace.sm),
                AetherButton.primary(
                  label: '同意',
                  size: AetherButtonSize.sm,
                  onPressed: () => syncProvider.approveIncomingRequest(request.id),
                ),
              ],
            ),
          ),
        ],
        if (syncProvider.isSyncing) ...[
          const SizedBox(height: AetherSpace.lg + 2),
          AetherProgress.linear(
            size: 6,
            value: syncProvider.progress,
            trackColor: cfg.borderSubtle.withValues(alpha: 0.45),
          ),
        ],
        const AetherDivider(),
        const AetherSectionHeader(title: '发现的设备'),
        if (devices.isEmpty)
          AetherSurface(
            level: AetherSurfaceLevel.flat,
            color: cfg.bgHover,
            borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
            padding: const EdgeInsets.all(AetherSpace.xl),
            child: Text(
              '还没有发现设备。请确认两台设备在同一局域网，并且都打开了 Aetheria。',
              style: AetherType.bodySmStyle(cfg.textSecondary).copyWith(height: 1.5),
            ),
          )
        else
          for (final device in devices) ...[
            SettingsSyncDeviceTile(
              cfg: cfg,
              device: device,
              libraryProvider: libraryProvider,
              audioProvider: audioProvider,
              syncProvider: syncProvider,
              onPull: onPullDevice,
            ),
            const SizedBox(height: AetherSpace.lg - 2),
          ],
        const SizedBox(height: AetherSpace.md),
        Text(
          '* 第一版是曲库镜像覆盖：从选中设备同步到本机后，歌曲、音源版本、歌词、标签、歌单和 files 文件夹会以对方为准；主题、悬浮歌词、音频处理等本机设置不会同步。对方没有的本机文件会删除，同步前会自动备份当前库。',
          style: AetherType.captionStyle(cfg.textSecondary).copyWith(height: 1.5),
        ),
      ],
    );
  }
}

class SettingsSyncDeviceTile extends StatelessWidget {
  const SettingsSyncDeviceTile({
    super.key,
    required this.cfg,
    required this.device,
    required this.libraryProvider,
    required this.audioProvider,
    required this.syncProvider,
    required this.onPull,
  });

  final AppThemeConfig cfg;
  final SyncDevice device;
  final LibraryProvider libraryProvider;
  final AudioPlayerProvider audioProvider;
  final SyncProvider syncProvider;
  final SettingsSyncPullHandler onPull;

  @override
  Widget build(BuildContext context) {
    return AetherSurface(
      level: AetherSurfaceLevel.flat,
      color: cfg.bgHover,
      borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
      padding: const EdgeInsets.all(AetherSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, color: cfg.accent, size: AetherIconSize.lg),
          const SizedBox(width: AetherSpace.lg - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.bodyStyle(cfg.textPrimary).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AetherSpace.xs),
                Text(
                  device.endpoint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.captionStyle(cfg.textSecondary),
                ),
                const SizedBox(height: AetherSpace.sm),
                Wrap(
                  spacing: AetherSpace.sm,
                  runSpacing: AetherSpace.xs,
                  children: [
                    SettingsSyncMetricPill(
                      cfg: cfg,
                      icon: Icons.library_music_outlined,
                      label: '${device.songCount} 首',
                    ),
                    SettingsSyncMetricPill(
                      cfg: cfg,
                      icon: Icons.layers_outlined,
                      label: '${device.versionCount} 个版本',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AetherSpace.lg - 2),
          AetherButton.primary(
            label: '同步到本机',
            icon: Icons.download,
            size: AetherButtonSize.sm,
            onPressed: syncProvider.isSyncing
                ? null
                : () => onPull(
                    context,
                    cfg,
                    device,
                    libraryProvider,
                    audioProvider,
                    syncProvider,
                  ),
          ),
        ],
      ),
    );
  }
}
