import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';

class SettingsModal extends StatelessWidget {
  const SettingsModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => const SettingsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<UIThemeProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final cfg = themeProvider.currentTheme;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: GlassPanel(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings, color: cfg.textMain, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '系统设置',
                          style: TextStyle(
                            fontSize: 16,
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
                const SizedBox(height: 24),

                // Theme Selector
                Text(
                  '切换界面主题风格',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
                ),
                const SizedBox(height: 10),
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
                    const SizedBox(width: 12),
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
                    const SizedBox(width: 12),
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

                // Library Path
                Text(
                  '本地托管音乐库路径',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cfg.bgHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cfg.border),
                  ),
                  child: SelectableText(
                    libraryProvider.libraryPath,
                    style: TextStyle(fontSize: 12, color: cfg.textMain, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 24),

                // Danger Zone
                Text(
                  '危险操作区域',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _confirmReset(context, libraryProvider),
                  icon: const Icon(Icons.delete_forever, size: 16, color: Colors.redAccent),
                  label: const Text('一键重置数据库并清空全部数据', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 24),

                // About section
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  '关于 Aetheria',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
                ),
                const SizedBox(height: 6),
                Text(
                  '软件版本: v0.1.0 (Portable)\n数据引擎: SQLite 3 & Symphonia/Lofty (Rust)\n开源许可: GNU AGPL v3 License\n界面渲染: Flutter 3 & Rust (FRB v2)',
                  style: TextStyle(fontSize: 11, color: cfg.textSub, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            color: isActive ? cfg.accent : Colors.transparent,
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

  void _confirmReset(BuildContext context, LibraryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重置？'),
        content: const Text('这将会清空数据库中所有的歌曲、版本和歌单信息，并且删除托管文件夹中的物理文件。此操作无法撤销！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // pop alert
              Navigator.of(context).pop(); // pop settings modal
              try {
                await provider.resetLibrary();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('数据库重置完成，已重新载入默认标签')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('重置失败: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('确定重置'),
          ),
        ],
      ),
    );
  }
}
