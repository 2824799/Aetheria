import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/tag_ordering.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_dropdown.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/core/widgets/color_picker_field.dart';
import 'package:aetheria/features/library/ui/tag_manager_priority_list.dart';
import 'package:aetheria/src/rust/models/song.dart';

const _defaultColor = '#3b82f6';

/// Create, edit and delete tags: the tag list beside an editor in wide
/// windows, and one scrolling column on phones.
class TagManagerModal extends StatefulWidget {
  const TagManagerModal({super.key});

  static void show(BuildContext context) {
    showAetherModalPage<void>(
      context: context,
      builder: (context) => const TagManagerModal(),
    );
  }

  @override
  State<TagManagerModal> createState() => _TagManagerModalState();
}

class _TagManagerModalState extends State<TagManagerModal> {
  final _nameController = TextEditingController();
  final _customCategoryController = TextEditingController();

  /// One of [kPresetTagCategories]; [kDefaultTagCategory] means "use the text field".
  String _category = kDefaultTagCategory;
  String _color = _defaultColor;
  PlatformInt64? _editingTagId;

  bool get _isEditing => _editingTagId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  void _startEdit(Tag tag) {
    final category = effectiveTagCategory(tag);
    final isPreset =
        category != kDefaultTagCategory &&
        kPresetTagCategories.contains(category);
    setState(() {
      _editingTagId = tag.id;
      _nameController.text = tag.name;
      _category = isPreset ? category : kDefaultTagCategory;
      _customCategoryController.text =
          isPreset || category == kDefaultTagCategory ? '' : category;
      _color = tag.color ?? _defaultColor;
    });
  }

  void _resetForm() {
    setState(() {
      _editingTagId = null;
      _nameController.clear();
      _customCategoryController.clear();
      _category = kDefaultTagCategory;
      _color = _defaultColor;
    });
  }

  String get _resolvedCategory {
    if (_category != kDefaultTagCategory) return _category;
    final typed = _customCategoryController.text.trim();
    return typed.isEmpty ? kDefaultTagCategory : typed;
  }

  Future<void> _submit(LibraryProvider library) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final editingId = _editingTagId;
    try {
      if (editingId == null) {
        await library.addTag(name, _color, _resolvedCategory);
      } else {
        await library.updateTag(editingId, name, _color, _resolvedCategory);
      }
      if (!mounted) return;
      _resetForm();
      showAetherToast(
        context,
        message: editingId == null ? '标签已创建' : '标签已更新',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '保存失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _delete(LibraryProvider library, Tag tag) async {
    final confirmed = await showAetherConfirmDialog(
      context: context,
      title: '删除标签',
      message: '确定删除标签“${tag.name}”吗？它会从所有歌曲上移除。',
      confirmLabel: '删除',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await library.deleteTag(tag.id);
      if (!mounted) return;
      if (_editingTagId == tag.id) _resetForm();
      showAetherToast(context, message: '标签已删除', kind: AetherToastKind.success);
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '删除失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;
    final mediaSize = MediaQuery.sizeOf(context);

    final editor = _TagEditor(
      isEditing: _isEditing,
      nameController: _nameController,
      customCategoryController: _customCategoryController,
      category: _category,
      color: _color,
      onCategoryChanged: (value) => setState(() => _category = value),
      onColorChanged: (value) => setState(() => _color = value),
      onSubmit: () => _submit(library),
      onCancelEdit: _resetForm,
    );
    final groups = groupOrderedTags(library.orderedTags);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : mediaSize.width;
        final availHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : mediaSize.height;
        final wide = availWidth >= 768;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: wide ? 760 : double.infinity,
              height: wide
                  ? (availHeight - AetherSpace.massive * 2).clamp(360.0, 600.0)
                  : availHeight * 0.86,
              margin: EdgeInsets.symmetric(
                horizontal: wide ? AetherSpace.xxxl : AetherSpace.lg,
                vertical: wide ? AetherSpace.massive : AetherSpace.xxl,
              ),
              child: AetherSurface(
                level: AetherSurfaceLevel.overlay,
                borderRadius: BorderRadius.circular(AetherRadius.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(tagCount: library.tags.length),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: groups.isEmpty
                                      ? const _NoTags()
                                      : TagPriorityList(
                                          groups: groups,
                                          editingTagId: _editingTagId,
                                          onMoveCategory:
                                              library.moveTagCategory,
                                          onMoveTag: library.moveTagInCategory,
                                          onEditTag: _startEdit,
                                          onDeleteTag: (tag) =>
                                              _delete(library, tag),
                                        ),
                                ),
                                Container(
                                  width: 304,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(color: cfg.borderSubtle),
                                    ),
                                  ),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      AetherSpace.xxl,
                                      AetherSpace.xs,
                                      AetherSpace.xxl,
                                      AetherSpace.xxl,
                                    ),
                                    child: editor,
                                  ),
                                ),
                              ],
                            )
                          : CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AetherSpace.xxxl,
                                    ),
                                    child: editor,
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: AetherSpace.xl),
                                ),
                                SliverToBoxAdapter(
                                  child: Divider(height: 1, color: cfg.divider),
                                ),
                                if (groups.isEmpty)
                                  const SliverToBoxAdapter(
                                    child: SizedBox(
                                      height: 220,
                                      child: _NoTags(),
                                    ),
                                  )
                                else
                                  SliverTagPriorityList(
                                    groups: groups,
                                    editingTagId: _editingTagId,
                                    onMoveCategory: library.moveTagCategory,
                                    onMoveTag: library.moveTagInCategory,
                                    onEditTag: _startEdit,
                                    onDeleteTag: (tag) => _delete(library, tag),
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
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tagCount});

  final int tagCount;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xxxl,
        AetherSpace.xl,
        AetherSpace.lg,
        AetherSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('标签管理', style: AetherType.titleStyle(cfg.textPrimary)),
          const SizedBox(width: AetherSpace.md),
          Expanded(
            child: Text(
              tagCount == 0 ? '' : '$tagCount 个 · 拖拽或点箭头调整显示顺序',
              style: AetherType.bodySmStyle(cfg.textTertiary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AetherIconButton(
            icon: Icons.close_rounded,
            color: cfg.textSecondary,
            size: 32,
            iconSize: AetherIconSize.lg,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _NoTags extends StatelessWidget {
  const _NoTags();

  @override
  Widget build(BuildContext context) {
    return const AetherEmptyState(
      icon: Icons.label_outline_rounded,
      title: '还没有标签',
      message: '创建标签后，可以在歌曲详情里给歌曲打标签，并按标签筛选',
    );
  }
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({
    required this.isEditing,
    required this.nameController,
    required this.customCategoryController,
    required this.category,
    required this.color,
    required this.onCategoryChanged,
    required this.onColorChanged,
    required this.onSubmit,
    required this.onCancelEdit,
  });

  final bool isEditing;
  final TextEditingController nameController;
  final TextEditingController customCategoryController;
  final String category;
  final String color;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onColorChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEditing ? '编辑标签' : '新建标签',
          style: AetherType.titleSmStyle(cfg.textPrimary),
        ),
        const SizedBox(height: AetherSpace.xl),
        _FieldLabel('名称'),
        AetherTextField(
          controller: nameController,
          hintText: '如：抒情',
          height: AetherSpace.controlHeight,
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: AetherSpace.xl),
        _FieldLabel('类别'),
        AetherDropdown<String>(
          value: category,
          items: [
            for (final preset in kPresetTagCategories)
              AetherDropdownItem(value: preset, label: preset),
          ],
          onChanged: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
        if (category == kDefaultTagCategory) ...[
          const SizedBox(height: AetherSpace.md),
          AetherTextField(
            controller: customCategoryController,
            hintText: '自定义类别名（可留空）',
            height: AetherSpace.controlHeight,
            onSubmitted: (_) => onSubmit(),
          ),
        ],
        const SizedBox(height: AetherSpace.xl),
        _FieldLabel('颜色'),
        ColorPickerField(value: color, cfg: cfg, onChanged: onColorChanged),
        const SizedBox(height: AetherSpace.xxxl),
        // The submit button follows the name field without rebuilding the
        // whole modal on every keystroke.
        ListenableBuilder(
          listenable: nameController,
          builder: (context, _) => AetherButton.primary(
            label: isEditing ? '保存修改' : '创建标签',
            expanded: true,
            onPressed: nameController.text.trim().isEmpty ? null : onSubmit,
          ),
        ),
        if (isEditing) ...[
          const SizedBox(height: AetherSpace.md),
          AetherButton.ghost(
            label: '取消编辑',
            expanded: true,
            onPressed: onCancelEdit,
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpace.sm),
      child: Text(
        text,
        style: AetherType.labelStyle(context.tokens.textSecondary),
      ),
    );
  }
}
