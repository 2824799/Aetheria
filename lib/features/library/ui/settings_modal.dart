import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/features/library/ui/library_import.dart';
import 'package:aetheria/features/library/ui/settings/settings_actions.dart';
import 'package:aetheria/features/library/ui/settings/settings_developer_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_floating_lyrics_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_library_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_playback_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_sync_tab.dart';
import 'package:aetheria/features/library/ui/settings/settings_theme_tab.dart';

enum _Category {
  theme('外观', Icons.palette_outlined),
  playback('播放', Icons.graphic_eq_rounded),
  floatingLyrics('桌面歌词', Icons.subtitles_outlined),
  library('音乐库', Icons.folder_outlined),
  sync('局域网同步', Icons.sync_alt_rounded),
  developer('开发者', Icons.terminal_rounded);

  const _Category(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Settings: a category list beside its page in wide windows, and a list that
/// drills into one page at a time on phones and in narrow windows.
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
  /// Below this window width the two-column layout no longer fits.
  static const double _wideLayoutMinWidth = 720;

  _Category _wideCategory = _Category.theme;

  /// Narrow layout only: null shows the category list.
  _Category? _narrowCategory;

  @override
  Widget build(BuildContext context) {
    // Platform decides which options exist; width decides the layout, so a
    // narrow desktop window gets the drill-down list instead of a squeezed
    // two-column view.
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final size = MediaQuery.sizeOf(context);
    final wide = isDesktop && size.width >= _wideLayoutMinWidth;
    final narrowCategory = _narrowCategory;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: wide ? size.width.clamp(720.0, 920.0) : double.infinity,
          height: wide ? size.height.clamp(520.0, 680.0) : size.height * 0.78,
          margin: EdgeInsets.symmetric(
            horizontal: wide ? AetherSpace.xxxl : AetherSpace.xl,
            vertical: AetherSpace.massive,
          ),
          child: AetherSurface(
            level: AetherSurfaceLevel.overlay,
            borderRadius: BorderRadius.circular(AetherRadius.lg),
            child: wide
                ? _buildWide(context)
                : Column(
                    children: [
                      _Header(
                        title: narrowCategory?.label ?? '设置',
                        onBack: narrowCategory == null
                            ? null
                            : () => setState(() => _narrowCategory = null),
                      ),
                      Expanded(
                        child: narrowCategory == null
                            ? _buildCategoryMenu(context)
                            : _CategoryPage(
                                category: narrowCategory,
                                isDesktop: isDesktop,
                                padding: const EdgeInsets.all(AetherSpace.xl),
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final cfg = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 188,
          decoration: BoxDecoration(
            color: cfg.bgHover,
            border: Border(right: BorderSide(color: cfg.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AetherSpace.xxl,
                  AetherSpace.xxl,
                  AetherSpace.xxl,
                  AetherSpace.lg,
                ),
                child: Text(
                  '设置',
                  style: AetherType.titleLgStyle(cfg.textPrimary),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.md,
                  ),
                  children: [
                    for (final category in _Category.values)
                      AetherListTile(
                        icon: category.icon,
                        title: category.label,
                        dense: true,
                        selected: category == _wideCategory,
                        onTap: () =>
                            setState(() => _wideCategory = category),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _Header(title: _wideCategory.label),
              Expanded(
                child: _CategoryPage(
                  // A fresh scroll position for every category.
                  key: ValueKey(_wideCategory),
                  category: _wideCategory,
                  isDesktop: true,
                  padding: const EdgeInsets.fromLTRB(
                    AetherSpace.xxxl,
                    AetherSpace.xs,
                    AetherSpace.xxxl,
                    AetherSpace.xxxl,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryMenu(BuildContext context) {
    final cfg = context.tokens;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.md,
        vertical: AetherSpace.md,
      ),
      children: [
        for (final category in _Category.values)
          AetherListTile(
            icon: category.icon,
            title: category.label,
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: cfg.textTertiary,
              size: AetherIconSize.lg,
            ),
            onTap: () => setState(() => _narrowCategory = category),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        onBack == null ? AetherSpace.xxxl : AetherSpace.lg,
        AetherSpace.xl,
        AetherSpace.lg,
        AetherSpace.md,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            AetherIconButton(
              icon: Icons.arrow_back_rounded,
              size: 32,
              iconSize: AetherIconSize.lg,
              tooltip: '返回',
              onPressed: onBack,
            ),
            const SizedBox(width: AetherSpace.sm),
          ],
          Expanded(
            child: Text(title, style: AetherType.titleStyle(cfg.textPrimary)),
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
    );
  }
}

/// One settings page. Watches only the providers its category reads, so e.g.
/// playback progress does not rebuild the theme page.
class _CategoryPage extends StatelessWidget {
  const _CategoryPage({
    super.key,
    required this.category,
    required this.isDesktop,
    required this.padding,
  });

  final _Category category;
  final bool isDesktop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final Widget page;
    switch (category) {
      case _Category.theme:
        page = SettingsThemeTab(
          cfg: cfg,
          themeProvider: context.watch<UIThemeProvider>(),
        );
      case _Category.playback:
        final audio = context.watch<AudioPlayerProvider>();
        page = SettingsPlaybackTab(
          cfg: cfg,
          audioProvider: audio,
          isDesktop: isDesktop,
          onShowCustomBufferDialog: () =>
              showCustomBufferDialog(context, audio),
        );
      case _Category.floatingLyrics:
        page = SettingsFloatingLyricsTab(
          cfg: cfg,
          provider: context.watch<FloatingLyricsProvider>(),
          isDesktop: isDesktop,
        );
      case _Category.library:
        final library = context.watch<LibraryProvider>();
        page = SettingsLibraryTab(
          cfg: cfg,
          libraryProvider: library,
          isDesktop: isDesktop,
          onChangeLibraryPath: () => changeLibraryPath(context, library),
          onImportFiles: () => importAudioFiles(context, library),
          onImportFolder: () => importAudioFolder(context, library),
        );
      case _Category.sync:
        final library = context.watch<LibraryProvider>();
        final audio = context.read<AudioPlayerProvider>();
        final sync = context.watch<SyncProvider>();
        page = SettingsSyncTab(
          cfg: cfg,
          libraryProvider: library,
          syncProvider: sync,
          onPullDevice: (device) => confirmPullFromDevice(
            context,
            device,
            library: library,
            audio: audio,
            sync: sync,
          ),
        );
      case _Category.developer:
        page = SettingsDeveloperTab(
          cfg: cfg,
          audioProvider: context.watch<AudioPlayerProvider>(),
        );
    }
    return SingleChildScrollView(padding: padding, child: page);
  }
}
