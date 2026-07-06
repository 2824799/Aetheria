import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.42),
      builder: (context) => const SettingsModal(),
    );
  }

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _AudioOutputInfoView extends StatelessWidget {
  const _AudioOutputInfoView({required this.cfg, required this.audioProvider});

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
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(cfg: cfg, label: '设备', value: deviceName),
            _InfoPill(
              cfg: cfg,
              label: '格式',
              value: info == null
                  ? 'unknown'
                  : '${info.sampleRate} Hz / ${info.channels}ch / ${info.sampleFormat}',
            ),
            _InfoPill(
              cfg: cfg,
              label: '队列缓冲',
              value:
                  '${info?.outputBufferMs ?? audioProvider.pitchBufferMs} ms',
            ),
            _InfoPill(
              cfg: cfg,
              label: '1%low 队列余量',
              value: '${info?.queuedMs ?? 0} ms',
            ),
            _InfoPill(
              cfg: cfg,
              label: '设备缓冲',
              value: info?.bufferSize ?? 'unknown',
            ),
            _InfoPill(
              cfg: cfg,
              label: '延迟模式',
              value: _outputLatencyModeLabel(latencyMode),
            ),
            _InfoPill(cfg: cfg, label: '峰值', value: peakDb),
            _InfoPill(cfg: cfg, label: '保护计数', value: clippedSamples),
            _InfoPill(cfg: cfg, label: '欠载', value: underruns),
          ],
        ),
        if (hasUnderrun) ...[
          const SizedBox(height: 8),
          Text(
            '检测到输出欠载，请提高处理缓冲或关闭高质量选项。',
            style: TextStyle(color: cfg.accent, fontSize: 10),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cfg.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: cfg.textSub,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cfg.textMain, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingLyricPreview extends StatelessWidget {
  const _FloatingLyricPreview({required this.cfg, required this.provider});

  final AppThemeConfig cfg;
  final FloatingLyricsProvider provider;

  @override
  Widget build(BuildContext context) {
    final textAlign = switch (provider.align) {
      FloatingLyricAlign.left => TextAlign.left,
      FloatingLyricAlign.right => TextAlign.right,
      FloatingLyricAlign.center => TextAlign.center,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cfg.border),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: provider.opacity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '这是一行正在播放的悬浮歌词',
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: provider.playedColor,
                fontSize: provider.fontSize.clamp(8, 38),
                fontWeight: provider.boldCurrentLine
                    ? FontWeight.w900
                    : FontWeight.w600,
                height: 1.1,
                shadows: provider.textShadowEnabled
                    ? [
                        Shadow(
                          color: provider.shadowColor,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
            SizedBox(height: provider.lineGap.clamp(0, 18)),
            if (provider.showTranslation)
              Text(
                'Floating lyric preview',
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: provider.unplayedColor.withOpacity(0.78),
                  fontSize: provider.fontSize.clamp(8, 38) * 0.46,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            if (provider.showNextLine) ...[
              SizedBox(height: provider.lineGap.clamp(0, 18)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '下一行歌词会在这里轻轻等着',
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: provider.unplayedColor.withOpacity(0.72),
                      fontSize: provider.fontSize.clamp(8, 38) * 0.58,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  if (provider.compactMultiline) ...[
                    SizedBox(height: provider.lineGap.clamp(0, 18) * 0.45),
                    Text(
                      '紧凑模式会继续显示更多行',
                      textAlign: textAlign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: provider.unplayedColor.withOpacity(0.55),
                        fontSize: provider.fontSize.clamp(8, 38) * 0.48,
                        fontWeight: FontWeight.w500,
                        height: 1.05,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsModalState extends State<SettingsModal> {
  String _activeTab = 'theme'; // For Desktop view
  String?
  _selectedCategory; // For Mobile view: null = Level 1 menu, non-null = Level 2 detail page
  bool _settingsImporting = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<UIThemeProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final floatingLyricsProvider = context.watch<FloatingLyricsProvider>();
    final cfg = themeProvider.currentTheme;

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    if (isDesktop) {
      // Desktop: Split sidebar + content layout
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width.clamp(720.0, 920.0),
            height: MediaQuery.of(context).size.height.clamp(520.0, 680.0),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: GlassPanel(
              blur: 30,
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.settings, color: cfg.textMain, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '系统设置',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: cfg.textMain,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: cfg.textSub, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cfg.border),

                  // Body
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sidebar
                        Container(
                          width: 140,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: cfg.border),
                            ),
                            color: Colors.black.withOpacity(0.02),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _buildSidebarItem(
                                'theme',
                                Icons.palette_outlined,
                                '个性外观',
                                cfg,
                              ),
                              _buildSidebarItem(
                                'playback',
                                Icons.play_circle_outline,
                                '播放设置',
                                cfg,
                              ),
                              _buildSidebarItem(
                                'floatingLyrics',
                                Icons.closed_caption_outlined,
                                '桌面歌词',
                                cfg,
                              ),
                              _buildSidebarItem(
                                'library',
                                Icons.folder_open_outlined,
                                '音乐库管理',
                                cfg,
                              ),
                              _buildSidebarItem(
                                'sync',
                                Icons.sync_alt,
                                '局域网同步',
                                cfg,
                              ),
                            ],
                          ),
                        ),

                        // Content
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: _buildActiveTabContent(
                              cfg,
                              libraryProvider,
                              audioProvider,
                              syncProvider,
                              floatingLyricsProvider,
                              themeProvider,
                              isDesktop,
                              _activeTab,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // Mobile: Hierarchical menu (Level 1 list / Level 2 full-screen details)
      final showLevel2 = _selectedCategory != null;
      final currentCategoryTitle = _selectedCategory == 'theme'
          ? '个性外观'
          : _selectedCategory == 'playback'
          ? '播放设置'
          : _selectedCategory == 'floatingLyrics'
          ? '桌面歌词'
          : _selectedCategory == 'sync'
          ? '局域网同步'
          : '音乐库管理';

      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.78,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: GlassPanel(
              blur: 30,
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            if (showLevel2) ...[
                              IconButton(
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: cfg.textMain,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedCategory = null;
                                  });
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currentCategoryTitle,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: cfg.textMain,
                                ),
                              ),
                            ] else ...[
                              Icon(
                                Icons.settings,
                                color: cfg.textMain,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '系统设置',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: cfg.textMain,
                                ),
                              ),
                            ],
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: cfg.textSub, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cfg.border),

                  // Body
                  Expanded(
                    child: showLevel2
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _buildActiveTabContent(
                              cfg,
                              libraryProvider,
                              audioProvider,
                              syncProvider,
                              floatingLyricsProvider,
                              themeProvider,
                              isDesktop,
                              _selectedCategory!,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _buildMobileMenuItem(
                                'theme',
                                Icons.palette_outlined,
                                '个性外观',
                                cfg,
                              ),
                              _buildMobileMenuItem(
                                'playback',
                                Icons.play_circle_outline,
                                '播放设置',
                                cfg,
                              ),
                              _buildMobileMenuItem(
                                'floatingLyrics',
                                Icons.closed_caption_outlined,
                                '桌面歌词',
                                cfg,
                              ),
                              _buildMobileMenuItem(
                                'library',
                                Icons.folder_open_outlined,
                                '音乐库管理',
                                cfg,
                              ),
                              _buildMobileMenuItem(
                                'sync',
                                Icons.sync_alt,
                                '局域网同步',
                                cfg,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSidebarItem(
    String tabId,
    IconData icon,
    String label,
    AppThemeConfig cfg,
  ) {
    final isActive = _activeTab == tabId;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tabId;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? cfg.accent.withOpacity(0.08) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? cfg.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? cfg.accent : cfg.textSub),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? cfg.accent : cfg.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMenuItem(
    String tabId,
    IconData icon,
    String label,
    AppThemeConfig cfg,
  ) {
    return ListTile(
      leading: Icon(icon, color: cfg.textMain, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: cfg.textMain,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: cfg.textSub, size: 16),
      onTap: () {
        setState(() {
          _selectedCategory = tabId;
        });
      },
    );
  }

  Widget _buildActiveTabContent(
    AppThemeConfig cfg,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    SyncProvider syncProvider,
    FloatingLyricsProvider floatingLyricsProvider,
    UIThemeProvider themeProvider,
    bool isDesktop,
    String activeTab,
  ) {
    switch (activeTab) {
      case 'sync':
        return _buildSyncTab(cfg, libraryProvider, audioProvider, syncProvider);
      case 'floatingLyrics':
        return _buildFloatingLyricsTab(cfg, floatingLyricsProvider, isDesktop);
      case 'playback':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '音频播放行为',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 12),
            if (!isDesktop) ...[
              SwitchListTile(
                title: Text(
                  '与其他应用一起播放',
                  style: TextStyle(
                    color: cfg.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '开启后允许本软件与其他音频应用同时混音播放而不被打断。',
                  style: TextStyle(color: cfg.textSub, fontSize: 11),
                ),
                value: audioProvider.playAlongside,
                onChanged: (val) {
                  audioProvider.setPlayAlongside(val);
                },
                activeColor: cfg.accent,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: cfg.border),
              const SizedBox(height: 12),
            ],
            Text(
              '主动音量均衡',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(
                '启用音量均衡',
                style: TextStyle(
                  color: cfg.textMain,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '根据歌单音量水平，按比例自动压低大声音歌曲的音量，不提升声音小的歌曲。',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              value: audioProvider.volumeBalanceEnabled,
              onChanged: (val) {
                audioProvider.setVolumeBalanceEnabled(val);
              },
              activeColor: cfg.accent,
              contentPadding: EdgeInsets.zero,
            ),
            if (audioProvider.volumeBalanceEnabled) ...[
              const SizedBox(height: 4),
              Text(
                '提示：极速导入时仅采样前几秒估算音量。如需追求最佳均衡效果，请前往 “音乐库管理” 菜单中点击 “刷新并重新扫描歌曲数据” 按钮以计算全歌精确分贝值。',
                style: TextStyle(color: cfg.accent, fontSize: 10),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '均衡强度: ${(audioProvider.volumeBalanceStrength * 100).round()}%',
                    style: TextStyle(color: cfg.textMain, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: audioProvider.volumeBalanceStrength,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      activeColor: cfg.accent,
                      inactiveColor: cfg.border,
                      onChanged: (val) {
                        audioProvider.setVolumeBalanceStrength(val);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Divider(height: 1, color: cfg.border),
            const SizedBox(height: 12),
            Text(
              '输出状态',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 8),
            _AudioOutputInfoView(cfg: cfg, audioProvider: audioProvider),
            const SizedBox(height: 10),
            Text(
              '设备输出延迟:',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '控制系统音频设备本身的回调块大小：默认跟随系统；低延迟响应更快但更容易欠载；稳定模式使用更大的设备块来减少爆音风险。',
              style: TextStyle(color: cfg.textSub, fontSize: 10, height: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('共享默认', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.outputLatencyMode == 'shared-default',
                  onSelected: (_) =>
                      audioProvider.setOutputLatencyMode('shared-default'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.outputLatencyMode == 'shared-default'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('共享低延迟', style: TextStyle(fontSize: 10)),
                  selected:
                      audioProvider.outputLatencyMode == 'shared-low-latency',
                  onSelected: (_) =>
                      audioProvider.setOutputLatencyMode('shared-low-latency'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color:
                        audioProvider.outputLatencyMode == 'shared-low-latency'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('共享稳定', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.outputLatencyMode == 'shared-stable',
                  onSelected: (_) =>
                      audioProvider.setOutputLatencyMode('shared-stable'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.outputLatencyMode == 'shared-stable'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: cfg.border),
            const SizedBox(height: 12),
            Text(
              '输出音调调节器',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: audioProvider.pitchEnabled,
              title: Text(
                audioProvider.pitchEnabled ? '已启用输出变调' : '已关闭输出变调',
                style: TextStyle(
                  color: cfg.textMain,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                audioProvider.pitchEnabled
                    ? '启用后可调整播放输出音高，但会带来额外处理延迟。'
                    : '关闭后会绕过变调处理，保留当前半音设置供后续再次启用。',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              activeColor: cfg.accent,
              onChanged: (value) => audioProvider.setPitchEnabled(value),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '音调调节: ${audioProvider.pitchSemitones > 0 ? '+' : ''}${audioProvider.pitchSemitones.toStringAsFixed(1)} 半音',
                  style: TextStyle(color: cfg.textMain, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: audioProvider.pitchSemitones,
                    min: -12.0,
                    max: 12.0,
                    divisions: 24,
                    activeColor: cfg.accent,
                    inactiveColor: cfg.border,
                    onChanged: audioProvider.pitchEnabled
                        ? (val) {
                            audioProvider.setPitchSemitones(val);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '处理缓冲: ${audioProvider.pitchBufferMs} ms',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '这是软件内部预先解码和 DSP 处理好的音频队列长度，表示当前播放点之后大约有多少毫秒音频已经准备好送往设备。',
              style: TextStyle(color: cfg.textSub, fontSize: 10, height: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(
                    '超低延迟 120ms',
                    style: TextStyle(fontSize: 10),
                  ),
                  selected: audioProvider.pitchBufferMs == 120,
                  onSelected: (_) => audioProvider.setPitchBufferMs(120),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchBufferMs == 120
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('平衡 240ms', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchBufferMs == 240,
                  onSelected: (_) => audioProvider.setPitchBufferMs(240),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchBufferMs == 240
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('稳定 480ms', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchBufferMs == 480,
                  onSelected: (_) => audioProvider.setPitchBufferMs(480),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchBufferMs == 480
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text(
                    '高容错 960ms',
                    style: TextStyle(fontSize: 10),
                  ),
                  selected: audioProvider.pitchBufferMs == 960,
                  onSelected: (_) => audioProvider.setPitchBufferMs(960),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchBufferMs == 960
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: Text(
                    [120, 240, 480, 960].contains(audioProvider.pitchBufferMs)
                        ? '自定义...'
                        : '自定义 ${audioProvider.pitchBufferMs}ms',
                    style: const TextStyle(fontSize: 10),
                  ),
                  selected: ![
                    120,
                    240,
                    480,
                    960,
                  ].contains(audioProvider.pitchBufferMs),
                  onSelected: (_) =>
                      _showCustomBufferDialog(context, cfg, audioProvider),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color:
                        ![
                          120,
                          240,
                          480,
                          960,
                        ].contains(audioProvider.pitchBufferMs)
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '变调算法选择:',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(
                    '专业保速 (Rubber Band)',
                    style: TextStyle(fontSize: 10),
                  ),
                  selected: audioProvider.pitchAlgorithm == 'rubberband',
                  onSelected: audioProvider.pitchEnabled
                      ? (_) => audioProvider.setPitchAlgorithm('rubberband')
                      : null,
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchAlgorithm == 'rubberband'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('重采样变速', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchAlgorithm == 'resample',
                  onSelected: audioProvider.pitchEnabled
                      ? (_) => audioProvider.setPitchAlgorithm('resample')
                      : null,
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.pitchAlgorithm == 'resample'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rubber Band 窗口:',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('低延迟', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.rubberbandWindow == 'latency',
                  onSelected:
                      audioProvider.pitchEnabled &&
                          audioProvider.pitchAlgorithm == 'rubberband'
                      ? (_) => audioProvider.setRubberbandWindow('latency')
                      : null,
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.rubberbandWindow == 'latency'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('高质量', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.rubberbandWindow == 'quality',
                  onSelected:
                      audioProvider.pitchEnabled &&
                          audioProvider.pitchAlgorithm == 'rubberband'
                      ? (_) => audioProvider.setRubberbandWindow('quality')
                      : null,
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.rubberbandWindow == 'quality'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: audioProvider.rubberbandFormantPreserved,
              title: Text(
                '保留人声音色',
                style: TextStyle(
                  color: cfg.textMain,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '适合人声升降调，可能增加处理压力。',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              activeColor: cfg.accent,
              onChanged:
                  audioProvider.pitchEnabled &&
                      audioProvider.pitchAlgorithm == 'rubberband'
                  ? (value) =>
                        audioProvider.setRubberbandFormantPreserved(value)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              '重采样质量:',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('标准', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.resamplerQuality == 'standard',
                  onSelected: (_) =>
                      audioProvider.setResamplerQuality('standard'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.resamplerQuality == 'standard'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
                ChoiceChip(
                  label: const Text('高质量 sinc', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.resamplerQuality == 'high',
                  onSelected: (_) => audioProvider.setResamplerQuality('high'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(
                    color: audioProvider.resamplerQuality == 'high'
                        ? cfg.accent
                        : cfg.textMain,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: audioProvider.peakProtectionEnabled,
              title: Text(
                '峰值保护',
                style: TextStyle(
                  color: cfg.textMain,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'DSP 后自动留出约 -1dB headroom，避免隐藏削波。',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              activeColor: cfg.accent,
              onChanged: (value) =>
                  audioProvider.setPeakProtectionEnabled(value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: audioProvider.ditherEnabled,
              title: Text(
                '整数输出抖动',
                style: TextStyle(
                  color: cfg.textMain,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '仅在设备不是 f32 输出时生效，降低量化失真。',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              activeColor: cfg.accent,
              onChanged: (value) => audioProvider.setDitherEnabled(value),
            ),
          ],
        );
      case 'library':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地音乐数据库',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 16),
            Text('当前托管路径：', style: TextStyle(fontSize: 11, color: cfg.textSub)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cfg.bgHover,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cfg.border),
              ),
              child: SelectableText(
                libraryProvider.libraryPath,
                style: TextStyle(
                  fontSize: 11,
                  color: cfg.textMain,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isDesktop) ...[
              OutlinedButton.icon(
                onPressed: () => _changeLibraryPath(context, libraryProvider),
                icon: Icon(
                  Icons.drive_file_rename_outline,
                  size: 14,
                  color: cfg.accent,
                ),
                label: Text(
                  '选择新托管路径',
                  style: TextStyle(color: cfg.accent, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  side: BorderSide(color: cfg.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '* 注意：修改路径后，软件将会在新文件夹下重新初始化并读取 database.db。',
                style: TextStyle(
                  fontSize: 10,
                  color: cfg.textSub,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              Text(
                '* 移动端系统路径由应用安全托管，无需且不支持自定义修改。',
                style: TextStyle(
                  fontSize: 11,
                  color: cfg.textSub,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _settingsImporting
                        ? null
                        : () => _importFilesFromSettings(
                            context,
                            libraryProvider,
                          ),
                    icon: _settingsImporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.audio_file, size: 14),
                    label: const Text('导入音频', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cfg.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _settingsImporting
                        ? null
                        : () => _importFolderFromSettings(
                            context,
                            libraryProvider,
                          ),
                    icon: const Icon(Icons.folder_open, size: 14),
                    label: const Text('导入目录', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cfg.accent,
                      side: BorderSide(color: cfg.accent.withOpacity(0.65)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: cfg.border),
            const SizedBox(height: 16),
            Text(
              '数据维护与重构',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: libraryProvider.isRefreshingDatabase
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await libraryProvider.refreshDatabase();
                          if (!mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('歌曲数据已全部刷新完成！')),
                          );
                        },
                  icon: libraryProvider.isRefreshingDatabase
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 14),
                  label: Text(
                    libraryProvider.isRefreshingDatabase
                        ? '正在刷新中...'
                        : '刷新扫描全部歌曲',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cfg.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: libraryProvider.isRefreshingDatabase
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await libraryProvider.refreshDatabase(
                            onlyUnscanned: true,
                          );
                          if (!mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('新增歌曲扫描已完成！')),
                          );
                        },
                  icon: const Icon(Icons.playlist_add_check, size: 14),
                  label: const Text('刷新扫描新增歌曲', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cfg.accent,
                    side: BorderSide(color: cfg.accent.withOpacity(0.65)),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            if (libraryProvider.isRefreshingDatabase) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: libraryProvider.refreshProgressTotal > 0
                      ? libraryProvider.refreshProgressCurrent /
                            libraryProvider.refreshProgressTotal
                      : null,
                  color: cfg.accent,
                  backgroundColor: cfg.border.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                libraryProvider.refreshProgressTotal > 0
                    ? '已完成 ${libraryProvider.refreshProgressCurrent} / ${libraryProvider.refreshProgressTotal} 首歌曲'
                    : '正在准备刷新任务...',
                style: TextStyle(
                  fontSize: 10,
                  color: cfg.textMain,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                libraryProvider.refreshProgressLabel.isNotEmpty
                    ? libraryProvider.refreshProgressLabel
                    : '正在深度重扫音频属性与响度信息，旧库里解析失败的 M4A 时长也会在这一轮里重新校正。',
                style: TextStyle(fontSize: 10, color: cfg.textSub, height: 1.5),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '* 全量扫描会重新处理所有音频；新增扫描只处理尚未完整扫描的版本。完整扫描会写入标记，后续新增扫描会自动跳过它们。',
              style: TextStyle(fontSize: 10, color: cfg.textSub, height: 1.5),
            ),
          ],
        );
      case 'theme':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '界面主题风格',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cfg.textSub,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildThemeCard(
                    context,
                    title: '深邃暗色',
                    type: AppThemeType.dark,
                    previewGradient: const RadialGradient(
                      center: Alignment.center,
                      radius: 1.0,
                      colors: [Color(0xFF0F172A), Color(0xFF020617)],
                    ),
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildThemeCard(
                    context,
                    title: '纯净亮色',
                    type: AppThemeType.light,
                    previewGradient: const LinearGradient(
                      colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                    ),
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildThemeCard(
                    context,
                    title: '温润粉樱',
                    type: AppThemeType.pink,
                    previewGradient: const LinearGradient(
                      colors: [Color(0xFFFFF5F5), Color(0xFFFFE4E6)],
                    ),
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, color: cfg.border),
            const SizedBox(height: 12),
            Text(
              '数据引擎: SQLite 3 & Symphonia/Lofty (Rust)\n界面渲染: Flutter 3 & Rust (FRB v2)',
              style: TextStyle(fontSize: 10, color: cfg.textSub, height: 1.5),
            ),
          ],
        );
    }
  }

  Widget _buildFloatingLyricsTab(
    AppThemeConfig cfg,
    FloatingLyricsProvider provider,
    bool isDesktop,
  ) {
    final maxWindowWidth = isDesktop ? 1800.0 : 1080.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isDesktop ? '电脑桌面歌词' : '安卓悬浮歌词',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cfg.textSub,
          ),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.enabled,
          title: Text(
            provider.enabled ? '已显示悬浮歌词' : '显示悬浮歌词',
            style: TextStyle(
              color: cfg.textMain,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            isDesktop
                ? '开启后会显示独立透明歌词窗口，支持拖动、置顶和锁定穿透。'
                : '开启后会通过系统悬浮窗显示当前播放歌词，需要授予悬浮窗权限。',
            style: TextStyle(color: cfg.textSub, fontSize: 11),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setEnabled,
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 8),
          FutureBuilder<bool>(
            future: NativeAudioHelper.canDrawOverlays(),
            builder: (context, snapshot) {
              final allowed = snapshot.data ?? false;
              return OutlinedButton.icon(
                onPressed: allowed
                    ? null
                    : () => NativeAudioHelper.requestOverlayPermission(),
                icon: Icon(
                  allowed ? Icons.verified_outlined : Icons.open_in_new,
                  size: 15,
                ),
                label: Text(
                  allowed ? '悬浮窗权限已授权' : '授予悬浮窗权限',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: allowed ? cfg.textSub : cfg.accent,
                  side: BorderSide(
                    color: allowed ? cfg.border : cfg.accent.withOpacity(0.65),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: cfg.border),
        const SizedBox(height: 12),
        Text(
          '窗口行为',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cfg.textSub,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.locked,
          title: Text(
            provider.locked ? '已锁定并穿透鼠标' : '锁定歌词窗口',
            style: TextStyle(
              color: cfg.textMain,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            provider.locked ? '锁定后歌词不会挡住鼠标点击。' : '关闭锁定时可以拖动窗口；打开锁定后可正常点击背后的应用。',
            style: TextStyle(color: cfg.textSub, fontSize: 11),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setLocked,
        ),
        if (isDesktop)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: provider.alwaysOnTop,
            title: Text(
              '保持置顶',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeColor: cfg.accent,
            onChanged: provider.setAlwaysOnTop,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.pauseFade,
          title: Text(
            '暂停时降低透明度',
            style: TextStyle(
              color: cfg.textMain,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setPauseFade,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('左对齐', style: TextStyle(fontSize: 10)),
              selected: provider.align == FloatingLyricAlign.left,
              onSelected: (_) => provider.setAlign(FloatingLyricAlign.left),
              selectedColor: cfg.accent.withOpacity(0.2),
              checkmarkColor: cfg.accent,
            ),
            ChoiceChip(
              label: const Text('居中', style: TextStyle(fontSize: 10)),
              selected: provider.align == FloatingLyricAlign.center,
              onSelected: (_) => provider.setAlign(FloatingLyricAlign.center),
              selectedColor: cfg.accent.withOpacity(0.2),
              checkmarkColor: cfg.accent,
            ),
            ChoiceChip(
              label: const Text('右对齐', style: TextStyle(fontSize: 10)),
              selected: provider.align == FloatingLyricAlign.right,
              onSelected: (_) => provider.setAlign(FloatingLyricAlign.right),
              selectedColor: cfg.accent.withOpacity(0.2),
              checkmarkColor: cfg.accent,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: cfg.border),
        const SizedBox(height: 12),
        Text(
          '歌词样式',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cfg.textSub,
          ),
        ),
        _buildSliderRow(
          cfg,
          label: '窗口宽度',
          valueText: '${provider.windowWidth.round()} px',
          value: provider.windowWidth.clamp(120, maxWindowWidth).toDouble(),
          min: 120,
          max: maxWindowWidth,
          divisions: isDesktop ? 168 : 96,
          onChanged: provider.setWindowWidth,
        ),
        _buildSliderRow(
          cfg,
          label: '窗口高度',
          valueText: '${provider.windowHeight.round()} px',
          value: provider.windowHeight,
          min: 36,
          max: 420,
          divisions: 96,
          onChanged: provider.setWindowHeight,
        ),
        _buildSliderRow(
          cfg,
          label: '字体大小',
          valueText: '${provider.fontSize.round()} px',
          value: provider.fontSize,
          min: 8,
          max: 72,
          divisions: 64,
          onChanged: provider.setFontSize,
        ),
        _buildSliderRow(
          cfg,
          label: '歌词间距',
          valueText: '${provider.lineGap.round()} px',
          value: provider.lineGap,
          min: 0,
          max: 32,
          divisions: 32,
          onChanged: provider.setLineGap,
        ),
        _buildSliderRow(
          cfg,
          label: '刷新帧率',
          valueText: '${provider.refreshFps} fps',
          value: provider.refreshFps.toDouble(),
          min: 10,
          max: 60,
          divisions: 10,
          onChanged: provider.setRefreshFps,
        ),
        _buildSliderRow(
          cfg,
          label: '透明度',
          valueText: '${(provider.opacity * 100).round()}%',
          value: provider.opacity,
          min: 0.2,
          max: 1.0,
          divisions: 16,
          onChanged: provider.setOpacity,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.boldCurrentLine,
          title: Text(
            '当前行加粗',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setBoldCurrentLine,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.zoomCurrentLine,
          title: Text(
            '当前行轻微放大',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setZoomCurrentLine,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.compactMultiline,
          title: Text(
            '紧凑显示多行',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          subtitle: Text(
            '开启后会在下一行下面继续显示更多后续歌词，适合小字号窗口。',
            style: TextStyle(color: cfg.textSub, fontSize: 10),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setCompactMultiline,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.textShadowEnabled,
          title: Text(
            '文字阴影',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          subtitle: Text(
            '这里只控制文字描边/阴影；歌词框背景默认不会常驻显示。',
            style: TextStyle(color: cfg.textSub, fontSize: 10),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setTextShadowEnabled,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.showTranslation,
          title: Text(
            '显示翻译歌词',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setShowTranslation,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: provider.showNextLine,
          title: Text(
            '显示下一行歌词',
            style: TextStyle(color: cfg.textMain, fontSize: 12),
          ),
          activeColor: cfg.accent,
          onChanged: provider.setShowNextLine,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildColorGroup(
              cfg,
              label: '未播放',
              selected: provider.unplayedColor,
              colors: const [
                Color(0xFFFFFFFF),
                Color(0xFFE0F2FE),
                Color(0xFFFFF7ED),
              ],
              onChanged: provider.setUnplayedColor,
            ),
            _buildColorGroup(
              cfg,
              label: '已播放',
              selected: provider.playedColor,
              colors: const [
                Color(0xFF22C55E),
                Color(0xFF38BDF8),
                Color(0xFFF97316),
                Color(0xFFEC4899),
              ],
              onChanged: provider.setPlayedColor,
            ),
            _buildColorGroup(
              cfg,
              label: '阴影',
              selected: provider.shadowColor,
              colors: const [
                Color(0x99000000),
                Color(0xAA111827),
                Color(0x770F172A),
              ],
              onChanged: provider.setShadowColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _FloatingLyricPreview(cfg: cfg, provider: provider),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: provider.resetStyle,
              icon: const Icon(Icons.restart_alt, size: 15),
              label: const Text('重置样式', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cfg.accent,
                side: BorderSide(color: cfg.accent.withOpacity(0.65)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (isDesktop)
              OutlinedButton.icon(
                onPressed: provider.resetWindowBounds,
                icon: const Icon(Icons.center_focus_strong, size: 15),
                label: const Text('重置窗口位置', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cfg.accent,
                  side: BorderSide(color: cfg.accent.withOpacity(0.65)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    AppThemeConfig cfg, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(color: cfg.textMain, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: cfg.accent,
            inactiveColor: cfg.border,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: TextStyle(color: cfg.textSub, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildColorGroup(
    AppThemeConfig cfg, {
    required String label,
    required Color selected,
    required List<Color> colors,
    required ValueChanged<Color> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: cfg.textSub, fontSize: 10)),
        const SizedBox(width: 6),
        for (final color in colors)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(color),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: selected == color ? cfg.accent : cfg.border,
                    width: selected == color ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSyncTab(
    AppThemeConfig cfg,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    SyncProvider syncProvider,
  ) {
    final devices = syncProvider.devices;
    final request = syncProvider.incomingRequest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '局域网镜像同步',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cfg.textSub,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cfg.bgHover,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cfg.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    syncProvider.isRunning
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: syncProvider.isRunning ? cfg.accent : cfg.textSub,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncProvider.statusMessage,
                      style: TextStyle(
                        color: cfg.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '本机名称：${syncProvider.localDeviceName}'
                '${syncProvider.localPort == null ? '' : ' · 端口 ${syncProvider.localPort}'}',
                style: TextStyle(color: cfg.textSub, fontSize: 11),
              ),
              if (syncProvider.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  syncProvider.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton.icon(
              onPressed: syncProvider.isRunning
                  ? () => syncProvider.announceNow()
                  : () => syncProvider.start(libraryProvider),
              icon: const Icon(Icons.radar, size: 14),
              label: Text(
                syncProvider.isRunning ? '刷新发现设备' : '启动同步服务',
                style: const TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cfg.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: syncProvider.clearDevices,
              icon: const Icon(Icons.cleaning_services_outlined, size: 14),
              label: const Text('清空列表', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cfg.accent,
                side: BorderSide(color: cfg.accent.withOpacity(0.65)),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        if (request != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notification_important_outlined,
                  size: 18,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${request.deviceName} 请求从本设备同步音乐库',
                    style: TextStyle(color: cfg.textMain, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => syncProvider.denyIncomingRequest(request.id),
                  child: const Text('拒绝'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () =>
                      syncProvider.approveIncomingRequest(request.id),
                  child: const Text('同意'),
                ),
              ],
            ),
          ),
        ],
        if (syncProvider.isSyncing) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: syncProvider.progress,
              color: cfg.accent,
              backgroundColor: cfg.border.withOpacity(0.45),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: cfg.border),
        const SizedBox(height: 16),
        Text(
          '发现的设备',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cfg.textSub,
          ),
        ),
        const SizedBox(height: 10),
        if (devices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cfg.bgHover,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cfg.border),
            ),
            child: Text(
              '还没有发现设备。请确认两台设备在同一局域网，并且都打开了 Aetheria。',
              style: TextStyle(color: cfg.textSub, fontSize: 11, height: 1.5),
            ),
          )
        else
          for (final device in devices) ...[
            _buildSyncDeviceTile(
              cfg,
              device,
              libraryProvider,
              audioProvider,
              syncProvider,
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 8),
        Text(
          '* 第一版是曲库镜像覆盖：从选中设备同步到本机后，歌曲、音源版本、歌词、标签、歌单和 files 文件夹会以对方为准；主题、悬浮歌词、音频处理等本机设置不会同步。对方没有的本机文件会删除，同步前会自动备份当前库。',
          style: TextStyle(fontSize: 10, color: cfg.textSub, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSyncDeviceTile(
    AppThemeConfig cfg,
    SyncDevice device,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    SyncProvider syncProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cfg.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, color: cfg.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cfg.textMain,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.endpoint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cfg.textSub, fontSize: 10),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildSyncMetricPill(
                      cfg,
                      Icons.library_music_outlined,
                      '${device.songCount} 首',
                    ),
                    _buildSyncMetricPill(
                      cfg,
                      Icons.layers_outlined,
                      '${device.versionCount} 个版本',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: syncProvider.isSyncing
                ? null
                : () => _confirmPullFromDevice(
                    context,
                    cfg,
                    device,
                    libraryProvider,
                    audioProvider,
                    syncProvider,
                  ),
            icon: const Icon(Icons.download, size: 14),
            label: const Text('同步到本机', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cfg.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncMetricPill(AppThemeConfig cfg, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cfg.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cfg.accent.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: cfg.accent),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: cfg.textMain,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPullFromDevice(
    BuildContext context,
    AppThemeConfig cfg,
    SyncDevice device,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    SyncProvider syncProvider,
  ) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从远端同步到本机？'),
        content: Text(
          '即将把 ${device.name} 的音乐库同步到本机。'
          '\n\n本机曲库数据和 files 文件夹会以对方为准，但主题、悬浮歌词、音频处理等本机设置不会被覆盖。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) {
      return;
    }

    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再次确认覆盖本机'),
        content: const Text(
          '本机多余的歌曲、歌词、数据库记录和 files 文件会被删除。同步前会备份当前库，但这仍然是一次覆盖操作；本机设置会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('覆盖本机'),
          ),
        ],
      ),
    );
    if (finalConfirm != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await syncProvider.pullFromDevice(
        device: device,
        libraryProvider: libraryProvider,
        audioProvider: audioProvider,
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已从 ${device.name} 同步到本机')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('同步失败: $e')));
    }
  }

  Future<void> _importFilesFromSettings(
    BuildContext context,
    LibraryProvider libraryProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
        allowMultiple: true,
      );
      final paths = result?.paths.whereType<String>().toList() ?? const [];
      if (paths.isEmpty) {
        return;
      }
      setState(() {
        _settingsImporting = true;
      });
      var success = 0;
      for (final path in paths) {
        try {
          await libraryProvider.importSong(path);
          success++;
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('已导入 $success 首歌曲')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _settingsImporting = false;
        });
      }
    }
  }

  Future<void> _importFolderFromSettings(
    BuildContext context,
    LibraryProvider libraryProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null || path.isEmpty) {
        return;
      }
      setState(() {
        _settingsImporting = true;
      });
      final filepaths = await music.scanDirectoryForPreview(dirPath: path);
      final previews = await music.previewAudioMetadata(filepaths: filepaths);
      var success = 0;
      for (final item in previews) {
        try {
          await libraryProvider.importSongWithMetadata(
            item.filepath,
            item.title,
            item.artist,
          );
          success++;
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('已从目录导入 $success 首歌曲')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('导入目录失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _settingsImporting = false;
        });
      }
    }
  }

  Widget _buildThemeCard(
    BuildContext context, {
    required String title,
    required AppThemeType type,
    required Gradient previewGradient,
    required UIThemeProvider themeProvider,
    required AppThemeConfig cfg,
  }) {
    final isActive = themeProvider.themeType == type;

    return InkWell(
      onTap: () => themeProvider.setTheme(type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? cfg.accent.withOpacity(0.5) : Colors.transparent,
            width: 2.0,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: previewGradient,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cfg.border),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? cfg.accent : cfg.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomBufferDialog(
    BuildContext context,
    AppThemeConfig cfg,
    AudioPlayerProvider audioProvider,
  ) async {
    final controller = TextEditingController(
      text: audioProvider.pitchBufferMs.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义处理缓冲'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '缓冲长度 (ms)',
            helperText: '可输入 60 到 1500 毫秒',
          ),
          onSubmitted: (_) {
            final value = int.tryParse(controller.text.trim());
            if (value != null) {
              Navigator.of(ctx).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cfg.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null) {
                Navigator.of(ctx).pop(value);
              }
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) {
      return;
    }
    await audioProvider.setPitchBufferMs(result.clamp(60, 1500).toInt());
  }

  Future<void> _changeLibraryPath(
    BuildContext context,
    LibraryProvider provider,
  ) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择新的托管音乐库路径',
      );
      if (selectedDirectory != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('aetheria-library-path', selectedDirectory);
        await provider.initializeLibrary(selectedDirectory);
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('托管路径已更新: $selectedDirectory')));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更改路径失败: $e')));
    }
  }
}
