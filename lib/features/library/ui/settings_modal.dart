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
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/ui/settings/settings_floating_lyrics_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_developer_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_sync_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_playback_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_library_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_theme_tab.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  static void show(BuildContext context) {
    showAetherModalPage<void>(
      context: context,
      builder: (context) => const SettingsModal(),
    );
  }

  @override
  State<SettingsModal> createState() => _SettingsModalState();
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
    final cfg = context.tokens;

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    if (isDesktop) {
      // Desktop: Split sidebar + content layout
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width.clamp(720.0, 920.0),
            height: MediaQuery.of(context).size.height.clamp(520.0, 680.0),
            margin: const EdgeInsets.symmetric(
              horizontal: AetherSpace.xxxl,
              vertical: AetherSpace.massive,
            ),
            child: AetherSurface(
              level: AetherSurfaceLevel.glass,
              blur: 18,
              borderRadius: BorderRadius.circular(AetherRadius.lg),
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
                            Icon(
                              Icons.settings,
                              color: cfg.textPrimary,
                              size: AetherIconSize.xl,
                            ),
                            const SizedBox(width: AetherSpace.md),
                            Text(
                              '系统设置',
                              style: AetherType.titleSmStyle(
                                cfg.textPrimary,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        AetherIconButton(
                          icon: Icons.close_rounded,
                          color: cfg.textSecondary,
                          size: 32,
                          iconSize: AetherIconSize.lg,
                          tooltip: '关闭设置',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const AetherDivider(margin: EdgeInsets.zero),

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
                              right: BorderSide(color: cfg.borderSubtle),
                            ),
                            color: cfg.bgHover,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                              vertical: AetherSpace.md,
                            ),
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
                                'developer',
                                Icons.developer_mode_rounded,
                                '开发者模式',
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
                            padding: const EdgeInsets.all(AetherSpace.xxl),
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
          : _selectedCategory == 'developer'
          ? '开发者模式'
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
            margin: const EdgeInsets.symmetric(
              horizontal: AetherSpace.xl,
              vertical: AetherSpace.massive,
            ),
            child: AetherSurface(
              level: AetherSurfaceLevel.glass,
              blur: 18,
              borderRadius: BorderRadius.circular(AetherRadius.lg),
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
                              AetherIconButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                color: cfg.textPrimary,
                                size: 32,
                                iconSize: AetherIconSize.md,
                                tooltip: '返回',
                                onPressed: () {
                                  setState(() {
                                    _selectedCategory = null;
                                  });
                                },
                              ),
                              const SizedBox(width: AetherSpace.md),
                              Text(
                                currentCategoryTitle,
                                style: AetherType.titleSmStyle(
                                  cfg.textPrimary,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ] else ...[
                              Icon(
                                Icons.settings,
                                color: cfg.textPrimary,
                                size: AetherIconSize.xl,
                              ),
                              const SizedBox(width: AetherSpace.md),
                              Text(
                                '系统设置',
                                style: AetherType.titleSmStyle(
                                  cfg.textPrimary,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ],
                        ),
                        AetherIconButton(
                          icon: Icons.close_rounded,
                          color: cfg.textSecondary,
                          size: 32,
                          iconSize: AetherIconSize.lg,
                          tooltip: '关闭设置',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const AetherDivider(margin: EdgeInsets.zero),

                  // Body
                  Expanded(
                    child: showLevel2
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(AetherSpace.xl),
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
                            padding: const EdgeInsets.symmetric(
                              vertical: AetherSpace.md,
                            ),
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
                                'developer',
                                Icons.developer_mode_rounded,
                                '开发者模式',
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
    return AetherListTile(
      icon: icon,
      title: label,
      dense: true,
      selected: isActive,
      onTap: () {
        setState(() {
          _activeTab = tabId;
        });
      },
    );
  }

  Widget _buildMobileMenuItem(
    String tabId,
    IconData icon,
    String label,
    AppThemeConfig cfg,
  ) {
    return AetherListTile(
      icon: icon,
      title: label,
      trailing: Icon(
        Icons.chevron_right,
        color: cfg.textSecondary,
        size: AetherIconSize.md,
      ),
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
        return SettingsSyncTab(
          cfg: cfg,
          libraryProvider: libraryProvider,
          audioProvider: audioProvider,
          syncProvider: syncProvider,
          onPullDevice: _confirmPullFromDevice,
        );
      case 'floatingLyrics':
        return SettingsFloatingLyricsTab(
          cfg: cfg,
          provider: floatingLyricsProvider,
          isDesktop: isDesktop,
        );
      case 'playback':
        return SettingsPlaybackTab(
          cfg: cfg,
          audioProvider: audioProvider,
          isDesktop: isDesktop,
          onShowCustomBufferDialog: () =>
              _showCustomBufferDialog(context, cfg, audioProvider),
        );
      case 'developer':
        return SettingsDeveloperTab(cfg: cfg, audioProvider: audioProvider);
      case 'library':
        return SettingsLibraryTab(
          cfg: cfg,
          libraryProvider: libraryProvider,
          isDesktop: isDesktop,
          settingsImporting: _settingsImporting,
          onChangeLibraryPath: () =>
              _changeLibraryPath(context, libraryProvider),
          onImportFiles: () =>
              _importFilesFromSettings(context, libraryProvider),
          onImportFolder: () =>
              _importFolderFromSettings(context, libraryProvider),
        );
      case 'theme':
      default:
        return SettingsThemeTab(cfg: cfg, themeProvider: themeProvider);
    }
  }

  Future<void> _confirmPullFromDevice(
    BuildContext context,
    AppThemeConfig cfg,
    SyncDevice device,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    SyncProvider syncProvider,
  ) async {
    final firstConfirm = await showAetherConfirmDialog(
      context: context,
      title: '从远端同步到本机？',
      message:
          '${device.name} 的音乐库将同步到本机。本机曲库与 files 会以对方为准；主题、悬浮歌词、音频处理等本机设置不会被覆盖。',
      confirmLabel: '继续',
    );
    if (firstConfirm != true || !context.mounted) {
      return;
    }

    final finalConfirm = await showAetherConfirmDialog(
      context: context,
      title: '再次确认覆盖本机',
      message: '本机多余的歌曲、歌词、数据库记录和 files 文件会被删除。同步前会备份当前库，但这仍然是一次覆盖操作；本机设置会保留。',
      confirmLabel: '确认覆盖',
      dangerous: true,
    );
    if (finalConfirm != true || !context.mounted) {
      return;
    }
    try {
      await syncProvider.pullFromDevice(
        device: device,
        libraryProvider: libraryProvider,
        audioProvider: audioProvider,
      );
      if (!mounted) {
        return;
      }
      showAetherToast(
        this.context,
        message: '已从 ${device.name} 同步到本机',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showAetherToast(
        this.context,
        message: '同步失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _importFilesFromSettings(
    BuildContext context,
    LibraryProvider libraryProvider,
  ) async {
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
      showAetherToast(
        this.context,
        message: '已导入 $success 首歌曲',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showAetherToast(
        this.context,
        message: '导入失败: $e',
        kind: AetherToastKind.error,
      );
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
      showAetherToast(
        this.context,
        message: '已从目录导入 $success 首歌曲',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showAetherToast(
        this.context,
        message: '导入目录失败: $e',
        kind: AetherToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _settingsImporting = false;
        });
      }
    }
  }

  Future<void> _showCustomBufferDialog(
    BuildContext context,
    AppThemeConfig cfg,
    AudioPlayerProvider audioProvider,
  ) async {
    final controller = TextEditingController(
      text: audioProvider.pitchBufferMs.toString(),
    );
    final result = await showAetherDialog<int>(
      context: context,
      builder: (ctx) {
        return AetherDialog(
          title: '自定义处理缓冲',
          content: AetherTextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            label: '缓冲长度 (ms)',
            hintText: '可输入 60 到 1500 毫秒',
            onSubmitted: (_) {
              final value = int.tryParse(controller.text.trim());
              if (value != null) {
                Navigator.of(ctx).pop(value);
              }
            },
          ),
          actions: [
            AetherButton.ghost(
              label: '取消',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            AetherButton.primary(
              label: '应用',
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value != null) {
                  Navigator.of(ctx).pop(value);
                }
              },
            ),
          ],
        );
      },
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
        showAetherToast(
          context,
          message: '托管路径已更新: $selectedDirectory',
          kind: AetherToastKind.info,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '更改路径失败: $e',
        kind: AetherToastKind.info,
      );
    }
  }
}
