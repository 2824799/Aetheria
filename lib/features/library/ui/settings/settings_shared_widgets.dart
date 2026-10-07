import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/color_picker_field.dart';

class SettingsAudioOutputInfoView extends StatelessWidget {
  const SettingsAudioOutputInfoView({
    super.key,
    required this.cfg,
    required this.audioProvider,
  });

  final AppThemeConfig cfg;
  final AudioPlayerProvider audioProvider;

  @override
  Widget build(BuildContext context) {
    final info = audioProvider.audioOutputInfo;
    final underruns = info?.underruns.toString() ?? '0';
    final clippedSamples = info?.clippedSamples.toString() ?? '0';
    final peakDb = info == null || info.peakDb.isInfinite
        ? '-inf'
        : '${info.peakDb.toStringAsFixed(1)} dBFS';
    final hasUnderrun = (info?.underruns ?? BigInt.zero) > BigInt.zero;
    final latencyMode =
        info?.outputLatencyMode ?? audioProvider.outputLatencyMode;
    final deviceName = _displayOutputDeviceName(info?.deviceName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AetherSpace.md,
          runSpacing: AetherSpace.md,
          children: [
            SettingsInfoPill(cfg: cfg, label: '设备', value: deviceName),
            SettingsInfoPill(
              cfg: cfg,
              label: '应用输出',
              value: info == null
                  ? 'unknown'
                  : '${info.sampleRate} Hz / ${info.channels}ch / ${info.sampleFormat}',
            ),
            SettingsInfoPill(
              cfg: cfg,
              label: '队列缓冲',
              value:
                  '${info?.outputBufferMs ?? audioProvider.pitchBufferMs} ms',
            ),
            SettingsInfoPill(
              cfg: cfg,
              label: '5秒内最低队列余量',
              value: '${info?.queuedMs ?? 0} ms',
            ),
            SettingsInfoPill(
              cfg: cfg,
              label: '设备缓冲',
              value: info?.bufferSize ?? 'unknown',
            ),
            SettingsInfoPill(
              cfg: cfg,
              label: '延迟模式',
              value: _outputLatencyModeLabel(latencyMode),
            ),
            SettingsInfoPill(cfg: cfg, label: '峰值', value: peakDb),
            SettingsInfoPill(cfg: cfg, label: '保护计数', value: clippedSamples),
            SettingsInfoPill(cfg: cfg, label: '欠载', value: underruns),
          ],
        ),
        const SizedBox(height: AetherSpace.md),
        Text(
          '此处显示应用交给系统的音频格式。系统混音、设备音效和蓝牙编码仍可能改变信号，不能据此确认逐位无损。',
          style: AetherType.captionStyle(cfg.textSecondary),
        ),
        if (audioProvider.volume != 1.0 ||
            audioProvider.volumeBalanceEnabled ||
            (audioProvider.pitchEnabled &&
                audioProvider.pitchSemitones.abs() > 0.01)) ...[
          const SizedBox(height: AetherSpace.sm),
          Text(
            '当前启用了音量调整、响度均衡或变调，输出波形会与原始音频不同。',
            style: AetherType.captionStyle(cfg.textSecondary),
          ),
        ],
        if (hasUnderrun) ...[
          const SizedBox(height: AetherSpace.md),
          Text(
            '检测到输出欠载，请提高处理缓冲，或使用共享稳定模式。',
            style: AetherType.captionStyle(cfg.accent),
          ),
        ],
      ],
    );
  }
}

String _displayOutputDeviceName(String? name) {
  final value = name?.trim();
  if (value == null || value.isEmpty || value.toLowerCase() == 'default') {
    return '系统默认输出';
  }
  return value;
}

String _outputLatencyModeLabel(String mode) {
  return switch (mode) {
    'shared-low-latency' => '共享低延迟',
    'shared-stable' => '共享稳定',
    _ => '共享默认',
  };
}

class SettingsInfoPill extends StatelessWidget {
  const SettingsInfoPill({
    super.key,
    required this.cfg,
    required this.label,
    required this.value,
  });

  final AppThemeConfig cfg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.lg - 2,
        vertical: AetherSpace.sm + 1,
      ),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
        border: Border.all(color: cfg.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: AetherType.captionStyle(
              cfg.textSecondary,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AetherType.captionStyle(cfg.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsFloatingLyricPreview extends StatefulWidget {
  const SettingsFloatingLyricPreview({
    super.key,
    required this.cfg,
    required this.provider,
  });
  final AppThemeConfig cfg;
  final FloatingLyricsProvider provider;
  @override
  State<SettingsFloatingLyricPreview> createState() =>
      _SettingsFloatingLyricPreviewState();
}

class _SettingsFloatingLyricPreviewState
    extends State<SettingsFloatingLyricPreview> {
  double _progress = 0.5;
  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final provider = widget.provider;
    final alignment = switch (provider.align) {
      FloatingLyricAlign.left => Alignment.centerLeft,
      FloatingLyricAlign.right => Alignment.centerRight,
      FloatingLyricAlign.center => Alignment.center,
    };
    final fontSize =
        provider.fontSize.clamp(8, 38).toDouble() *
        (provider.zoomCurrentLine ? 1.08 : 1);
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: provider.boldCurrentLine
          ? FontWeight.w700
          : FontWeight.normal,
    );
    const line = '让每一句歌词，都有自己的颜色';
    return AetherSurface(
      level: AetherSurfaceLevel.flat,
      color: cfg.bgHover,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('播放状态预览', style: AetherType.captionStyle(cfg.textSecondary)),
          const SizedBox(height: 12),
          Opacity(
            opacity: provider.opacity,
            child: Column(
              children: [
                Align(
                  alignment: alignment,
                  child: Stack(
                    children: [
                      if (provider.textShadowEnabled)
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(
                            color: Colors.transparent,
                            shadows: [
                              Shadow(
                                color: provider.shadowColor,
                                offset: const Offset(1.5, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            provider.playedColor,
                            provider.playedColor,
                            provider.unplayedColor,
                            provider.unplayedColor,
                          ],
                          stops: [0, _progress, _progress, 1],
                        ).createShader(bounds),
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                if (provider.showTranslation) ...[
                  SizedBox(height: provider.lineGap * 0.55),
                  Align(
                    alignment: alignment,
                    child: Text(
                      '翻译行预览',
                      style: TextStyle(
                        color: provider.unplayedColor.withValues(
                          alpha: provider.unplayedColor.a * 0.76,
                        ),
                        fontSize: fontSize * 0.42,
                      ),
                    ),
                  ),
                ],
                if (provider.showNextLine) ...[
                  SizedBox(height: provider.lineGap),
                  Align(
                    alignment: alignment,
                    child: Text(
                      '下一行歌词',
                      style: TextStyle(
                        color: provider.unplayedColor.withValues(
                          alpha: provider.unplayedColor.a * 0.66,
                        ),
                        fontSize: fontSize * 0.55,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsSliderRow(
            cfg: cfg,
            label: '预览进度',
            valueText: '${(_progress * 100).round()}%',
            value: _progress,
            onChanged: (value) => setState(() => _progress = value),
          ),
          if (provider.pauseFade)
            Text(
              '开启暂停淡出时，桌面歌词在暂停后会变淡。',
              style: AetherType.captionStyle(cfg.textSecondary),
            ),
        ],
      ),
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  final String title;
  const SettingsSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Text(title, style: AetherType.labelStyle(cfg.textSecondary));
  }
}

class SettingsSliderRow extends StatelessWidget {
  final AppThemeConfig cfg;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final bool enabled;

  const SettingsSliderRow({
    super.key,
    required this.cfg,
    required this.label,
    required this.valueText,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: AetherType.captionStyle(cfg.textSecondary),
            ),
          ),
          Expanded(
            child: AetherSlider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          const SizedBox(width: AetherSpace.sm),
          SizedBox(
            width: 72,
            child: Text(
              valueText,
              textAlign: TextAlign.end,
              style: AetherType.captionStyle(cfg.textPrimary).copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String settingsColorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color settingsColorFromHex(String hex, {int alpha = 0xFF}) {
  final clean = hex.replaceAll('#', '').toUpperCase();
  if (RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
    return Color((alpha << 24) | int.parse(clean, radix: 16));
  }
  if (RegExp(r'^[0-9A-F]{8}$').hasMatch(clean)) {
    return Color(int.parse(clean, radix: 16));
  }
  return AetherFallbackColors.accent;
}

class SettingsColorGroup extends StatelessWidget {
  const SettingsColorGroup({
    super.key,
    required this.cfg,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onChanged,
    this.onPreview,
  });

  final AppThemeConfig cfg;
  final String label;
  final Color selected;
  final List<Color> colors;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color>? onPreview;

  @override
  Widget build(BuildContext context) {
    final selectedArgb = selected.toARGB32();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AetherType.captionStyle(cfg.textSecondary)),
        const SizedBox(height: AetherSpace.sm),
        Wrap(
          spacing: AetherSpace.sm,
          runSpacing: AetherSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final color in colors)
              AetherPressable(
                onTap: () => onChanged(color),
                borderRadius: BorderRadius.circular(AetherRadius.full),
                pressScale: AetherMotion.pressScaleSubtle,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.toARGB32() == selectedArgb
                          ? cfg.accent
                          : cfg.borderSubtle,
                      width: color.toARGB32() == selectedArgb ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ColorPickerField(
              cfg: cfg,
              value: pickerColorHex(selected, includeAlpha: true),
              showPresets: false,
              enableAlpha: true,
              livePreview: true,
              onPreview: onPreview == null
                  ? null
                  : (hex) => onPreview!(settingsColorFromHex(hex)),
              onChanged: (hex) {
                final alpha = (selected.toARGB32() >> 24) & 0xFF;
                onChanged(settingsColorFromHex(hex, alpha: alpha));
              },
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsThemeCard extends StatelessWidget {
  const SettingsThemeCard({
    super.key,
    required this.title,
    required this.type,
    required this.previewGradient,
    required this.themeProvider,
    required this.cfg,
  });

  final String title;
  final AppThemeType type;
  final Gradient previewGradient;
  final UIThemeProvider themeProvider;
  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    final selected = themeProvider.themeType == type;
    return AetherPressable(
      onTap: () => themeProvider.setTheme(type),
      borderRadius: BorderRadius.circular(AetherRadius.lg),
      pressScale: AetherMotion.pressScaleSubtle,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.curve(context),
        padding: const EdgeInsets.all(AetherSpace.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AetherRadius.lg),
          border: Border.all(
            color: selected ? cfg.accent : cfg.borderSubtle,
            width: selected ? 1.6 : 1,
          ),
          color: selected ? cfg.selection : cfg.bgHover,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: previewGradient,
                borderRadius: BorderRadius.circular(AetherRadius.md),
                border: Border.all(color: cfg.borderSubtle),
              ),
            ),
            const SizedBox(height: AetherSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AetherType.labelStyle(
                selected ? cfg.accent : cfg.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSyncMetricPill extends StatelessWidget {
  const SettingsSyncMetricPill({
    super.key,
    required this.cfg,
    required this.label,
    this.icon,
    this.value,
  });

  final AppThemeConfig cfg;
  final String label;
  final IconData? icon;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isEmpty ? label : '$label $value';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.md,
        vertical: AetherSpace.xs,
      ),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(AetherRadius.full),
        border: Border.all(color: cfg.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AetherIconSize.sm, color: cfg.textSecondary),
            const SizedBox(width: AetherSpace.xs),
          ],
          Text(text, style: AetherType.captionStyle(cfg.textSecondary)),
        ],
      ),
    );
  }
}
