import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/core/widgets/color_picker_field.dart';
import 'package:aetheria/src/rust/models/song.dart';

class TagManagerModal extends StatefulWidget {
  const TagManagerModal({super.key});

  static const presets = ['流派', '语言', '情绪', '场景', '自定义'];

  static void show(BuildContext context) {
    final scrim = context.tokens.scrim;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: scrim,
      transitionDuration: AetherMotion.normal,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const TagManagerModal();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AetherMotion.out,
          reverseCurve: AetherMotion.out,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: AetherMotion.modalFromScale,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<TagManagerModal> createState() => _TagManagerModalState();
}

class _TagManagerModalState extends State<TagManagerModal> {
  final TextEditingController _tagNameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController(
    text: '自定义',
  );
  String _selectedCategory = '自定义';
  String _selectedColor = '#3b82f6';
  bool _isCustomCategory = false;
  PlatformInt64? _editingTagId;

  Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return AetherFallbackColors.neutral;
  }

  @override
  void dispose() {
    _tagNameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _startEdit(Tag tag) {
    setState(() {
      _editingTagId = tag.id;
      _tagNameController.text = tag.name;
      _selectedCategory = tag.category ?? '自定义';
      _isCustomCategory = !TagManagerModal.presets.contains(_selectedCategory);
      _categoryController.text =
          _isCustomCategory ? _selectedCategory : '自定义';
      _selectedColor = tag.color ?? '#3b82f6';
    });
  }

  void _resetForm() {
    setState(() {
      _editingTagId = null;
      _tagNameController.clear();
      _selectedCategory = '自定义';
      _isCustomCategory = false;
      _categoryController.text = '自定义';
      _selectedColor = '#3b82f6';
    });
  }

  void _onCategoryChanged(String? val) {
    if (val == null) return;
    setState(() {
      _selectedCategory = val;
      _isCustomCategory = val == '自定义';
      if (_isCustomCategory) {
        _categoryController.clear();
      }
    });
  }

  Future<void> _submitTag(LibraryProvider libraryProvider) async {
    final name = _tagNameController.text.trim();
    final category = _isCustomCategory
        ? (_categoryController.text.trim().isEmpty
            ? '自定义'
            : _categoryController.text.trim())
        : _selectedCategory;
    if (name.isEmpty) return;

    final wasEditing = _editingTagId != null;
    try {
      if (_editingTagId == null) {
        await libraryProvider.addTag(name, _selectedColor, category);
      } else {
        await libraryProvider.updateTag(
          _editingTagId!,
          name,
          _selectedColor,
          category,
        );
      }
      _resetForm();
      if (!mounted) return;
      showAetherToast(
        context,
        message: wasEditing ? '标签已更新' : '创建标签成功',
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

  Future<void> _deleteTag(LibraryProvider libraryProvider, Tag tag) async {
    try {
      await libraryProvider.deleteTag(tag.id);
      if (_editingTagId == tag.id) _resetForm();
      if (!mounted) return;
      showAetherToast(
        context,
        message: '标签已删除',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '删除失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  InputDecoration _dropdownDecoration(AppThemeConfig cfg) {
    return InputDecoration(
      filled: true,
      fillColor: cfg.bgHover,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AetherRadius.md),
        borderSide: BorderSide(color: cfg.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AetherRadius.md),
        borderSide: BorderSide(color: cfg.borderSubtle),
      ),
    );
  }

  Widget _categoryDropdown(AppThemeConfig cfg, {double? width}) {
    final dropdownValue = TagManagerModal.presets.contains(_selectedCategory)
        ? _selectedCategory
        : '自定义';

    final field = SizedBox(
      height: AetherSpace.controlHeight,
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('cat-$dropdownValue-$_editingTagId'),
        initialValue: dropdownValue,
        style: AetherType.bodyStyle(cfg.textPrimary),
        dropdownColor: cfg.bgPopover,
        decoration: _dropdownDecoration(cfg),
        items: TagManagerModal.presets
            .map(
              (cat) => DropdownMenuItem(
                value: cat,
                child: Text(cat, style: AetherType.bodyStyle(cfg.textPrimary)),
              ),
            )
            .toList(),
        onChanged: _onCategoryChanged,
      ),
    );
    return field;
  }

  Widget _buildForm(
    AppThemeConfig cfg,
    LibraryProvider libraryProvider, {
    required bool isCompact,
  }) {
    final submit = AetherButton.primary(
      label: _editingTagId == null ? '创建' : '保存',
      icon: _editingTagId == null ? Icons.add : Icons.save_outlined,
      size: AetherButtonSize.sm,
      expanded: isCompact,
      onPressed: () => _submitTag(libraryProvider),
    );

    final customCategory = AetherTextField(
      controller: _categoryController,
      hintText: '输入类别',
      height: AetherSpace.controlHeight,
      onChanged: (value) => _selectedCategory = value,
    );

    return AetherSurface(
      level: AetherSurfaceLevel.elevated,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: const EdgeInsets.all(AetherSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editingTagId == null ? '新建自定义标签' : '编辑已有标签',
            style: AetherType.labelStyle(cfg.textSecondary),
          ),
          const SizedBox(height: AetherSpace.md),
          AetherTextField(
            controller: _tagNameController,
            hintText: '标签名, 如: 抒情',
            height: AetherSpace.controlHeight,
          ),
          const SizedBox(height: AetherSpace.md),
          if (isCompact) ...[
            _categoryDropdown(cfg),
            if (_isCustomCategory) ...[
              const SizedBox(height: AetherSpace.md),
              customCategory,
            ],
            const SizedBox(height: AetherSpace.md),
            submit,
          ] else
            Row(
              children: [
                _categoryDropdown(cfg, width: 110),
                if (_isCustomCategory) ...[
                  const SizedBox(width: AetherSpace.md),
                  SizedBox(width: 110, child: customCategory),
                ],
                const SizedBox(width: AetherSpace.md),
                submit,
              ],
            ),
          if (_editingTagId != null) ...[
            const SizedBox(height: AetherSpace.md),
            Align(
              alignment: Alignment.centerRight,
              child: AetherButton.ghost(
                label: '取消编辑',
                size: AetherButtonSize.sm,
                onPressed: _resetForm,
              ),
            ),
          ],
          const SizedBox(height: AetherSpace.lg),
          ColorPickerField(
            value: _selectedColor,
            cfg: cfg,
            onChanged: (color) {
              setState(() => _selectedColor = color);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTagList(AppThemeConfig cfg, LibraryProvider libraryProvider) {
    return AetherSurface(
      level: AetherSurfaceLevel.flat,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      border: Border.all(color: cfg.borderSubtle),
      child: libraryProvider.tags.isEmpty
          ? const AetherEmptyState(
              icon: Icons.label_outline,
              title: '暂无标签',
              message: '在上方创建自定义标签',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
              itemCount: libraryProvider.tags.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: cfg.borderSubtle.withValues(alpha: 0.7),
              ),
              itemBuilder: (context, index) {
                final tag = libraryProvider.tags[index];
                final tagColor = tag.color != null
                    ? _parseHexColor(tag.color!)
                    : cfg.textPrimary;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.lg,
                    vertical: AetherSpace.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tagColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AetherSpace.md),
                      Expanded(
                        child: Text(
                          '[${tag.category ?? "自定义"}] ${tag.name}',
                          style: AetherType.labelStyle(tagColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AetherIconButton(
                        icon: Icons.edit_outlined,
                        size: 32,
                        iconSize: 16,
                        tooltip: '编辑',
                        onPressed: () => _startEdit(tag),
                      ),
                      AetherIconButton(
                        icon: Icons.delete_outline,
                        size: 32,
                        iconSize: 16,
                        color: cfg.danger,
                        tooltip: '删除',
                        onPressed: () => _deleteTag(libraryProvider, tag),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<UIThemeProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final cfg = themeProvider.currentTheme;
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 768;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isCompact ? media.size.width - 24 : 560,
            maxHeight: isCompact ? media.size.height * 0.9 : 720,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? AetherSpace.lg : AetherSpace.xxxl,
              vertical: isCompact ? AetherSpace.lg : AetherSpace.massive,
            ),
            child: AetherSurface(
              level: AetherSurfaceLevel.glass,
              borderRadius: BorderRadius.circular(AetherRadius.xl),
              padding: const EdgeInsets.all(AetherSpace.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isCompact ? '标签管理' : '管理已有标签',
                          style: AetherType.titleStyle(cfg.textPrimary),
                        ),
                      ),
                      AetherIconButton(
                        icon: Icons.close,
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AetherSpace.xxl),
                  _buildForm(cfg, libraryProvider, isCompact: isCompact),
                  const SizedBox(height: AetherSpace.xl),
                  Text(
                    '标签列表',
                    style: AetherType.labelStyle(cfg.textSecondary),
                  ),
                  const SizedBox(height: AetherSpace.md),
                  Expanded(child: _buildTagList(cfg, libraryProvider)),
                  const SizedBox(height: AetherSpace.xl),
                  AetherButton.secondary(
                    label: '关闭',
                    expanded: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
