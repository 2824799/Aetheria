import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/aether_choice_group.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_switch.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';

class SettingsPlaybackTab extends StatelessWidget {
  const SettingsPlaybackTab({
    super.key,
    required this.cfg,
    required this.audioProvider,
    required this.isDesktop,
    required this.onShowCustomBufferDialog,
  });

  final AppThemeConfig cfg;
  final AudioPlayerProvider audioProvider;
  final bool isDesktop;
  final VoidCallback onShowCustomBufferDialog;

  bool get _customBuffer =>
      ![120, 240, 480, 960].contains(audioProvider.pitchBufferMs);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AetherSectionHeader(title: '音频播放行为'),
        if (!isDesktop) ...[
          AetherSwitchTile(
            title: '与其他应用一起播放',
            subtitle: '开启后允许本软件与其他音频应用同时混音播放而不被打断。',
            value: audioProvider.playAlongside,
            onChanged: audioProvider.setPlayAlongside,
          ),
          const AetherDivider(),
        ],
        const AetherSectionHeader(title: '主动音量均衡'),
        AetherSwitchTile(
          title: '启用音量均衡',
          subtitle: '根据歌单音量水平，按比例自动压低大声音歌曲的音量，不提升声音小的歌曲。',
          value: audioProvider.volumeBalanceEnabled,
          onChanged: audioProvider.setVolumeBalanceEnabled,
        ),
        if (audioProvider.volumeBalanceEnabled) ...[
          const SizedBox(height: AetherSpace.xs),
          Text(
            '提示：极速导入时仅采样前几秒估算音量。如需追求最佳均衡效果，请前往 “音乐库管理” 菜单中点击 “刷新并重新扫描歌曲数据” 按钮以计算全歌精确分贝值。',
            style: AetherType.captionStyle(cfg.accent),
          ),
          SettingsSliderRow(
            cfg: cfg,
            label: '均衡强度',
            valueText:
                '${(audioProvider.volumeBalanceStrength * 100).round()}%',
            value: audioProvider.volumeBalanceStrength,
            min: 0,
            max: 1,
            divisions: 10,
            onChanged: audioProvider.setVolumeBalanceStrength,
          ),
        ],
        const AetherDivider(),
        const AetherSectionHeader(title: '输出状态'),
        SettingsAudioOutputInfoView(cfg: cfg, audioProvider: audioProvider),
        const SizedBox(height: AetherSpace.lg),
        Text('设备输出延迟', style: AetherType.labelStyle(cfg.textPrimary)),
        const SizedBox(height: AetherSpace.sm),
        Text(
          '控制系统音频设备本身的回调块大小：默认跟随系统；低延迟响应更快但更容易欠载；稳定模式使用更大的设备块来减少爆音风险。',
          style: AetherType.captionStyle(
            cfg.textSecondary,
          ).copyWith(height: 1.5),
        ),
        const SizedBox(height: AetherSpace.md),
        AetherChoiceGroup<String>(
          value: audioProvider.outputLatencyMode,
          onChanged: audioProvider.setOutputLatencyMode,
          options: const [
            AetherChoiceOption(value: 'shared-default', label: '共享默认'),
            AetherChoiceOption(value: 'shared-low-latency', label: '共享低延迟'),
            AetherChoiceOption(value: 'shared-stable', label: '共享稳定'),
          ],
        ),
        const AetherDivider(),
        const AetherSectionHeader(title: '输出音调调节器'),
        AetherSwitchTile(
          title: audioProvider.pitchEnabled ? '已启用输出变调' : '已关闭输出变调',
          subtitle: audioProvider.pitchEnabled
              ? '启用后可调整播放输出音高，但会带来额外处理延迟。'
              : '关闭后会绕过变调处理，保留当前半音设置供后续再次启用。',
          value: audioProvider.pitchEnabled,
          onChanged: audioProvider.setPitchEnabled,
        ),
        SettingsSliderRow(
          cfg: cfg,
          label: '音调调节',
          valueText:
              '${audioProvider.pitchSemitones > 0 ? '+' : ''}${audioProvider.pitchSemitones.toStringAsFixed(1)} st',
          value: audioProvider.pitchSemitones,
          min: -12,
          max: 12,
          divisions: 24,
          enabled: audioProvider.pitchEnabled,
          onChanged: audioProvider.setPitchSemitones,
        ),
        const SizedBox(height: AetherSpace.md),
        Text(
          '处理缓冲: ${audioProvider.pitchBufferMs} ms',
          style: AetherType.labelStyle(cfg.textPrimary),
        ),
        const SizedBox(height: AetherSpace.sm),
        Text(
          '这是软件内部预先解码和 DSP 处理好的音频队列长度，表示当前播放点之后大约有多少毫秒音频已经准备好送往设备。',
          style: AetherType.captionStyle(
            cfg.textSecondary,
          ).copyWith(height: 1.5),
        ),
        const SizedBox(height: AetherSpace.md),
        AetherChoiceGroup<int>(
          value: _customBuffer ? -1 : audioProvider.pitchBufferMs,
          onChanged: (value) {
            if (value < 0) {
              onShowCustomBufferDialog();
              return;
            }
            audioProvider.setPitchBufferMs(value);
          },
          options: [
            const AetherChoiceOption(value: 120, label: '超低延迟 120ms'),
            const AetherChoiceOption(value: 240, label: '平衡 240ms'),
            const AetherChoiceOption(value: 480, label: '稳定 480ms'),
            const AetherChoiceOption(value: 960, label: '高容错 960ms'),
            AetherChoiceOption(
              value: -1,
              label: _customBuffer
                  ? '自定义 ${audioProvider.pitchBufferMs}ms'
                  : '自定义...',
            ),
          ],
        ),
        const SizedBox(height: AetherSpace.md),
        Text('变调算法选择', style: AetherType.labelStyle(cfg.textPrimary)),
        const SizedBox(height: AetherSpace.sm),
        AetherChoiceGroup<String>(
          value: audioProvider.pitchAlgorithm,
          enabled: audioProvider.pitchEnabled,
          onChanged: audioProvider.setPitchAlgorithm,
          options: const [
            AetherChoiceOption(value: 'rubberband', label: 'Rubber Band'),
            AetherChoiceOption(value: 'resample', label: '重采样变速'),
          ],
        ),
        const SizedBox(height: AetherSpace.md),
        Text('Rubber Band 窗口', style: AetherType.labelStyle(cfg.textPrimary)),
        const SizedBox(height: AetherSpace.sm),
        AetherChoiceGroup<String>(
          value: audioProvider.rubberbandWindow,
          enabled:
              audioProvider.pitchEnabled &&
              audioProvider.pitchAlgorithm == 'rubberband',
          onChanged: audioProvider.setRubberbandWindow,
          options: const [
            AetherChoiceOption(value: 'latency', label: '低延迟'),
            AetherChoiceOption(value: 'quality', label: '高质量'),
          ],
        ),
        AetherSwitchTile(
          title: '保留人声音色',
          subtitle: '适合人声升降调，可能增加处理压力。',
          value: audioProvider.rubberbandFormantPreserved,
          enabled:
              audioProvider.pitchEnabled &&
              audioProvider.pitchAlgorithm == 'rubberband',
          onChanged: audioProvider.setRubberbandFormantPreserved,
        ),
        AetherSwitchTile(
          title: '仅人声升降调',
          subtitle: '变调中置成分并尽量保留左右声道背景乐器；中置乐器也可能受到影响。',
          value: audioProvider.rubberbandVocalOnlyPitch,
          enabled:
              audioProvider.pitchEnabled &&
              audioProvider.pitchAlgorithm == 'rubberband',
          onChanged: audioProvider.setRubberbandVocalOnlyPitch,
        ),
        const SizedBox(height: AetherSpace.md),
        Text('重采样质量', style: AetherType.labelStyle(cfg.textPrimary)),
        const SizedBox(height: AetherSpace.sm),
        AetherChoiceGroup<String>(
          value: audioProvider.resamplerQuality,
          onChanged: audioProvider.setResamplerQuality,
          options: const [
            AetherChoiceOption(value: 'standard', label: '标准'),
            AetherChoiceOption(value: 'high', label: '高质量 sinc'),
          ],
        ),
        AetherSwitchTile(
          title: '峰值保护',
          subtitle: 'DSP 后自动留出约 -1dB headroom，避免隐藏削波。',
          value: audioProvider.peakProtectionEnabled,
          onChanged: audioProvider.setPeakProtectionEnabled,
        ),
        AetherSwitchTile(
          title: '整数输出抖动',
          subtitle: '仅在设备不是 f32 输出时生效，降低量化失真。',
          value: audioProvider.ditherEnabled,
          onChanged: audioProvider.setDitherEnabled,
        ),
      ],
    );
  }
}
