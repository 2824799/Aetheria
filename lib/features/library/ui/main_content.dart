import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/features/library/ui/library_import.dart';
import 'package:aetheria/features/library/ui/song_list_summary.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';

/// Desktop library page: title, search, import, tag filter and the song table.
class MainContent extends StatefulWidget {
  final SongTableController? songTableController;

  const MainContent({super.key, this.songTableController});

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> {
  /// Scroll distance over which the tag pool folds away.
  static const double _tagCollapseDistance = 140;

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<double> _tagCollapseFactor = ValueNotifier(0);

  @override
  void dispose() {
    _searchController.dispose();
    _tagCollapseFactor.dispose();
    super.dispose();
  }

  bool _collapseTagsOnScroll(ScrollUpdateNotification notification) {
    final delta = notification.scrollDelta ?? 0;
    final draggingThumb =
        widget.songTableController?.isScrollbarDragging ?? false;
    if (notification.metrics.axis == Axis.vertical &&
        !draggingThumb &&
        delta > 0 &&
        _tagCollapseFactor.value < 1) {
      _tagCollapseFactor.value = math.min(
        1,
        _tagCollapseFactor.value + delta / _tagCollapseDistance,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xxxl,
        AetherSpace.xxl,
        AetherSpace.xxxl,
        AetherSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _PageTitle(library: library)),
              const SizedBox(width: AetherSpace.xl),
              SizedBox(
                width: 300,
                child: AetherSearchField(
                  controller: _searchController,
                  hintText: '搜索歌曲、歌手、专辑…',
                  onChanged: library.setSearchQuery,
                  onClear: () => library.setSearchQuery(''),
                ),
              ),
              const SizedBox(width: AetherSpace.md),
              _ImportButton(library: library),
            ],
          ),
          const SizedBox(height: AetherSpace.xl),
          ValueListenableBuilder<double>(
            valueListenable: _tagCollapseFactor,
            builder: (context, factor, _) => TagFilter(
              scrollCollapseFactor: factor,
              onExpandRequested: () => _tagCollapseFactor.value = 0,
            ),
          ),
          const SizedBox(height: AetherSpace.lg),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cfg.bg1,
                borderRadius: BorderRadius.circular(AetherRadius.lg),
                border: Border.all(color: cfg.borderSubtle),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AetherRadius.lg - 1),
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: _collapseTagsOnScroll,
                  child: SongTable(controller: widget.songTableController),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name of the list on screen and how many songs it shows.
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.library});

  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            songListTitle(library),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AetherType.displayStyle(cfg.textPrimary),
          ),
        ),
        const SizedBox(width: AetherSpace.lg),
        Text(
          songListCount(library),
          style: AetherType.bodyStyle(cfg.textTertiary),
        ),
      ],
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.library});

  final LibraryProvider library;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final belowButton = box.localToGlobal(
      Offset(0, box.size.height + AetherSpace.sm),
      ancestor: overlay,
    );

    final choice = await showAetherMenu<String>(
      context: context,
      globalPosition: belowButton,
      items: const [
        AetherMenuItem(
          value: 'files',
          label: '选择音频文件…',
          icon: Icons.audio_file_outlined,
        ),
        AetherMenuItem(
          value: 'folder',
          label: '选择文件夹…',
          icon: Icons.folder_outlined,
        ),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'files') {
      await importAudioFiles(context, library);
    } else if (choice == 'folder') {
      await importAudioFolder(context, library);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AetherButton.primary(
      label: '导入歌曲',
      icon: Icons.add_rounded,
      onPressed: () => _openMenu(context),
    );
  }
}
