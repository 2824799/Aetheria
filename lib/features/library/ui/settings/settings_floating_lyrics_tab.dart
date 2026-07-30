import 'dart:io';

import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_choice_group.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_switch.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';
import 'package:aetheria/services/native_audio_helper.dart';

class SettingsFloatingLyricsTab extends StatelessWidget {
  const SettingsFloatingLyricsTab({
    super.key,
    required this.cfg,
    required this.provider,
    required this.isDesktop,
  });

  final AppThemeConfig cfg;
  final FloatingLyricsProvider provider;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final maxWindowWidth = isDesktop ? 1800.0 : 1080.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AetherSectionHeader(
          title: isDesktop ? '电脑桌面歌词' : '安卓悬浮歌词',
        ),
        AetherSwitchTile(
          title: provider.enabled ? '已显示悬浮歌词' : '显示悬浮歌词',
          subtitle: isDesktop
              ? '开启后会显示独立透明歌词窗口，支持拖动、置顶和锁定穿透。'
              : '开启后会通过系统悬浮窗显示当前播放歌词，需要授予悬浮窗权限。',
          value: provider.enabled,
          onChanged: provider.setEnabled,
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: AetherSpace.md),
          FutureBuilder<bool>(
            future: NativeAudioHelper.canDrawOverlays(),
            builder: (context, snapshot) {
              final allowed = snapshot.data ?? false;
              return AetherButton.secondary(
                label: allowed ? '悬浮窗权限已授权' : '授予悬浮窗权限',
                icon: allowed ? Icons.verified_outlined : Icons.open_in_new,
                size: AetherButtonSize.sm,
                onPressed: allowed
                    ? null
                    : () => NativeAudioHelper.requestOverlayPermission(),
              );
            },
          ),
        ],
        const AetherDivider(),
        const AetherSectionHeader(title: '窗口行为'),
        AetherSwitchTile(
          title: provider.locked ? '已锁定并穿透鼠标' : '锁定歌词窗口',
          subtitle: provider.locked
              ? '锁定后歌词不会挡住鼠标点击。'
              : '关闭锁定时可以拖动窗口；打开锁定后可正常点击背后的应用。',
          value: provider.locked,
          onChanged: provider.setLocked,
        ),
        if (isDesktop)
          AetherSwitchTile(
            title: '保持置顶',
            value: provider.alwaysOnTop,
            onChanged: provider.setAlwaysOnTop,
          ),
        AetherSwitchTile(
          title: '暂停时降低透明度',
          value: provider.pauseFade,
          onChanged: provider.setPauseFade,
        ),
        const SizedBox(height: AetherSpace.sm),
        AetherChoiceGroup<FloatingLyricAlign>(
          value: provider.align,
          onChanged: provider.setAlign,
          options: const [
            AetherChoiceOption(value: FloatingLyricAlign.left, label: '左对齐'),
            AetherChoiceOption(value: FloatingLyricAlign.center, label: '居中'),
            AetherChoiceOption(value: FloatingLyricAlign.right, label: '右对齐'),
          ],
        ),
        const AetherDivider(),
        const AetherSectionHeader(title: '歌词样式'),
        SettingsSliderRow(
          cfg: cfg,
          label: '窗口宽度',
          valueText: '${provider.windowWidth.round()} px',
          value: provider.windowWidth.clamp(120, maxWindowWidth).toDouble(),
          min: 120,
          max: maxWindowWidth,
          divisions: isDesktop ? 168 : 96,
          onChanged: provider.setWindowWidth,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '窗口高度',
          valueText: '${provider.windowHeight.round()} px',
          value: provider.windowHeight,
          min: 36,
          max: 420,
          divisions: 96,
          onChanged: provider.setWindowHeight,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '字体大小',
          valueText: '${provider.fontSize.round()} px',
          value: provider.fontSize,
          min: 8,
          max: 72,
          divisions: 64,
          onChanged: provider.setFontSize,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '歌词间距',
          valueText: '${provider.lineGap.round()} px',
          value: provider.lineGap,
          min: 0,
          max: 32,
          divisions: 32,
          onChanged: provider.setLineGap,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '刷新帧率',
          valueText: '${provider.refreshFps} fps',
          value: provider.refreshFps.toDouble(),
          min: 10,
          max: 60,
          divisions: 10,
          onChanged: provider.setRefreshFps,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '透明度',
          valueText: '${(provider.opacity * 100).round()}%',
          value: provider.opacity,
          min: 0.2,
          max: 1.0,
          divisions: 16,
          onChanged: provider.setOpacity,
        ),
        AetherSwitchTile(
          title: '当前行加粗',
          value: provider.boldCurrentLine,
          onChanged: provider.setBoldCurrentLine,
        ),
        AetherSwitchTile(
          title: '当前行轻微放大',
          value: provider.zoomCurrentLine,
          onChanged: provider.setZoomCurrentLine,
        ),
        AetherSwitchTile(
          title: '紧凑显示多行',
          subtitle: '开启后会在下一行下面继续显示更多后续歌词，适合小字号窗口。',
          value: provider.compactMultiline,
          onChanged: provider.setCompactMultiline,
        ),
        AetherSwitchTile(
          title: '文字阴影',
          subtitle: '这里只控制文字描边/阴影；歌词框背景默认不会常驻显示。',
          value: provider.textShadowEnabled,
          onChanged: provider.setTextShadowEnabled,
        ),
        AetherSwitchTile(
          title: '显示翻译歌词',
          value: provider.showTranslation,
          onChanged: provider.setShowTranslation,
        ),
        AetherSwitchTile(
          title: '显示下一行歌词',
          value: provider.showNextLine,
          onChanged: provider.setShowNextLine,
        ),
        const SizedBox(height: AetherSpace.md),
        Wrap(
          spacing: AetherSpace.lg,
          runSpacing: AetherSpace.lg,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SettingsColorGroup(
              cfg: cfg,
              label: '未播放',
              selected: provider.unplayedColor,
              colors: AetherLyricPalettes.unplayed,
              onChanged: provider.setUnplayedColor,
            ),
            SettingsColorGroup(
              cfg: cfg,
              label: '已播放',
              selected: provider.playedColor,
              colors: AetherLyricPalettes.played,
              onChanged: provider.setPlayedColor,
            ),
            SettingsColorGroup(
              cfg: cfg,
              label: '阴影',
              selected: provider.shadowColor,
              colors: AetherLyricPalettes.shadow,
              onChanged: provider.setShadowColor,
            ),
          ],
        ),
        const SizedBox(height: AetherSpace.xl),
        SettingsFloatingLyricPreview(cfg: cfg, provider: provider),
        const SizedBox(height: AetherSpace.lg),
        Wrap(
          spacing: AetherSpace.lg - 2,
          runSpacing: AetherSpace.lg - 2,
          children: [
            AetherButton.secondary(
              label: '重置样式',
              icon: Icons.restart_alt,
              size: AetherButtonSize.sm,
              onPressed: provider.resetStyle,
            ),
            if (isDesktop)
              AetherButton.secondary(
                label: '重置窗口位置',
                icon: Icons.center_focus_strong,
                size: AetherButtonSize.sm,
                onPressed: provider.resetWindowBounds,
              ),
          ],
        ),
      ],
    );
  }
}
