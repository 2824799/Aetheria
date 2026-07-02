import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => const SettingsModal(),
    );
  }

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  String _activeTab = 'theme'; // For Desktop view
  String? _selectedCategory; // For Mobile view: null = Level 1 menu, non-null = Level 2 detail page

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<UIThemeProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final cfg = themeProvider.currentTheme;

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    if (isDesktop) {
      // Desktop: Split sidebar + content layout
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 580,
            height: 380,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: GlassPanel(
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 12),
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
                            border: Border(right: BorderSide(color: cfg.border)),
                            color: Colors.black.withOpacity(0.02),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _buildSidebarItem('theme', Icons.palette_outlined, '个性外观', cfg),
                              _buildSidebarItem('playback', Icons.play_circle_outline, '播放设置', cfg),
                              _buildSidebarItem('library', Icons.folder_open_outlined, '音乐库管理', cfg),
                            ],
                          ),
                        ),

                        // Content
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: _buildActiveTabContent(cfg, libraryProvider, audioProvider, themeProvider, isDesktop, _activeTab),
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
              : '音乐库管理';

      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: 420,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: GlassPanel(
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            if (showLevel2) ...[
                              IconButton(
                                icon: Icon(Icons.arrow_back, color: cfg.textMain, size: 20),
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
                            ]
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
                            child: _buildActiveTabContent(cfg, libraryProvider, audioProvider, themeProvider, isDesktop, _selectedCategory!),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _buildMobileMenuItem('theme', Icons.palette_outlined, '个性外观', cfg),
                              _buildMobileMenuItem('playback', Icons.play_circle_outline, '播放设置', cfg),
                              _buildMobileMenuItem('library', Icons.folder_open_outlined, '音乐库管理', cfg),
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

  Widget _buildSidebarItem(String tabId, IconData icon, String label, AppThemeConfig cfg) {
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
            Icon(
              icon,
              size: 16,
              color: isActive ? cfg.accent : cfg.textSub,
            ),
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

  Widget _buildMobileMenuItem(String tabId, IconData icon, String label, AppThemeConfig cfg) {
    return ListTile(
      leading: Icon(icon, color: cfg.textMain, size: 20),
      title: Text(
        label,
        style: TextStyle(color: cfg.textMain, fontSize: 13, fontWeight: FontWeight.w600),
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
    UIThemeProvider themeProvider,
    bool isDesktop,
    String activeTab,
  ) {
    switch (activeTab) {
      case 'playback':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '音频播放行为',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(
                '与其他应用一起播放',
                style: TextStyle(color: cfg.textMain, fontSize: 13, fontWeight: FontWeight.bold),
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
            Text(
              '主动音量均衡',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(
                '启用音量均衡',
                style: TextStyle(color: cfg.textMain, fontSize: 13, fontWeight: FontWeight.bold),
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
              '输出音调调节器',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
            ),
            const SizedBox(height: 8),
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
                    onChanged: (val) {
                      audioProvider.setPitchSemitones(val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '变调算法选择:',
              style: TextStyle(color: cfg.textMain, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('波形相似 (WSOLA)', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchAlgorithm == 'wsola',
                  onSelected: (_) => audioProvider.setPitchAlgorithm('wsola'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(color: audioProvider.pitchAlgorithm == 'wsola' ? cfg.accent : cfg.textMain),
                ),
                ChoiceChip(
                  label: const Text('时域叠加 (OLA)', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchAlgorithm == 'ola',
                  onSelected: (_) => audioProvider.setPitchAlgorithm('ola'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(color: audioProvider.pitchAlgorithm == 'ola' ? cfg.accent : cfg.textMain),
                ),
                ChoiceChip(
                  label: const Text('重采样变速', style: TextStyle(fontSize: 10)),
                  selected: audioProvider.pitchAlgorithm == 'resample',
                  onSelected: (_) => audioProvider.setPitchAlgorithm('resample'),
                  selectedColor: cfg.accent.withOpacity(0.2),
                  checkmarkColor: cfg.accent,
                  labelStyle: TextStyle(color: audioProvider.pitchAlgorithm == 'resample' ? cfg.accent : cfg.textMain),
                ),
              ],
            ),
          ],
        );
      case 'library':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地音乐数据库',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
            ),
            const SizedBox(height: 16),
            Text(
              '当前托管路径：',
              style: TextStyle(fontSize: 11, color: cfg.textSub),
            ),
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
                style: TextStyle(fontSize: 11, color: cfg.textMain, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),
            if (isDesktop) ...[
              OutlinedButton.icon(
                onPressed: () => _changeLibraryPath(context, libraryProvider),
                icon: Icon(Icons.drive_file_rename_outline, size: 14, color: cfg.accent),
                label: Text('选择新托管路径', style: TextStyle(color: cfg.accent, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  side: BorderSide(color: cfg.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '* 注意：修改路径后，软件将会在新文件夹下重新初始化并读取 database.db。',
                style: TextStyle(fontSize: 10, color: cfg.textSub, fontStyle: FontStyle.italic),
              ),
            ] else ...[
              Text(
                '* 移动端系统路径由应用安全托管，无需且不支持自定义修改。',
                style: TextStyle(fontSize: 11, color: cfg.textSub, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: cfg.border),
            const SizedBox(height: 16),
            Text(
              '数据维护与重构',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: libraryProvider.isRefreshingDatabase
                      ? null
                      : () async {
                          await libraryProvider.refreshDatabase();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('歌曲数据已全部刷新完成！')),
                            );
                          }
                        },
                  icon: libraryProvider.isRefreshingDatabase
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh, size: 14),
                  label: Text(
                    libraryProvider.isRefreshingDatabase ? '正在刷新中...' : '刷新并重新扫描歌曲数据',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cfg.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '* 点击将深度重新扫描所有音频（包括时长、比特率、声道、位深度），并完整解码全部音频文件以计算最精准的全局听感音量指标（耗时可能较长，请重新加载应用生效）。',
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
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

  Future<void> _changeLibraryPath(BuildContext context, LibraryProvider provider) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择新的托管音乐库路径',
      );
      if (selectedDirectory != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('aetheria-library-path', selectedDirectory);
        await provider.initializeLibrary(selectedDirectory);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('托管路径已更新: $selectedDirectory')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更改路径失败: $e')),
      );
    }
  }
}
