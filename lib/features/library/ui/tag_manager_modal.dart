import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';
import 'package:aetheria/core/widgets/color_picker_field.dart';
import 'package:aetheria/src/rust/models/song.dart';

class TagManagerModal extends StatefulWidget {
  const TagManagerModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.42),
      builder: (context) => const TagManagerModal(),
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
    return Colors.grey;
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
      final presets = ['流派', '语言', '情绪', '场景', '自定义'];
      _isCustomCategory = !presets.contains(_selectedCategory);
      _categoryController.text = _isCustomCategory ? _selectedCategory : '自定义';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(wasEditing ? '标签已更新' : '创建标签成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
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
          width: 560,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: GlassPanel(
            blur: 30,
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
                    Text(
                      '管理已有标签',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cfg.textMain,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: cfg.textSub, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Form to create tag
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cfg.bgHover,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cfg.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _editingTagId == null ? '新建自定义标签' : '编辑已有标签',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cfg.textSub,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _tagNameController,
                                style: TextStyle(
                                  color: cfg.textMain,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: '标签名, 如: 抒情',
                                  hintStyle: TextStyle(
                                    color: cfg.textSub.withOpacity(0.5),
                                  ),
                                  filled: true,
                                  fillColor: Colors.black.withOpacity(0.06),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: cfg.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: cfg.border),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 136,
                            height: 38,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              style: TextStyle(color: cfg.textMain, fontSize: 13),
                              dropdownColor: cfg.bgPanel,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.06),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cfg.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cfg.border)),
                              ),
                              items: ['流派', '语言', '情绪', '场景', '自定义']
                                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedCategory = val;
                                    _isCustomCategory = val == '自定义';
                                    if (_isCustomCategory) {
                                      _categoryController.clear();
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          if (_isCustomCategory) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              height: 38,
                              child: TextField(
                                controller: _categoryController,
                                style: TextStyle(color: cfg.textMain, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '输入类别',
                                  hintStyle: TextStyle(color: cfg.textSub.withOpacity(0.5)),
                                  filled: true,
                                  fillColor: Colors.black.withOpacity(0.06),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cfg.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cfg.border)),
                                ),
                                onChanged: (value) => _selectedCategory = value,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _submitTag(libraryProvider),
                            icon: Icon(
                              _editingTagId == null
                                  ? Icons.add
                                  : Icons.save_outlined,
                              size: 14,
                            ),
                            label: Text(
                              _editingTagId == null ? '创建' : '保存',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cfg.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_editingTagId != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _resetForm,
                            child: const Text(
                              '取消编辑',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ColorPickerField(
                        value: _selectedColor,
                        cfg: cfg,
                        onChanged: (color) {
                          setState(() {
                            _selectedColor = color;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tag List Manager
                Text(
                  '标签列表',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cfg.textSub,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cfg.border),
                    ),
                    child: libraryProvider.tags.isEmpty
                        ? Center(
                            child: Text(
                              '暂无标签',
                              style: TextStyle(
                                color: cfg.textSub,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: libraryProvider.tags.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: cfg.border.withOpacity(0.5),
                            ),
                            itemBuilder: (context, index) {
                              final tag = libraryProvider.tags[index];
                              final tagColor = tag.color != null
                                  ? _parseHexColor(tag.color!)
                                  : cfg.textMain;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: tagColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '[${tag.category ?? "自定义"}] ${tag.name}',
                                          style: TextStyle(
                                            color: tagColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            color: cfg.textSub,
                                            size: 18,
                                          ),
                                          onPressed: () => _startEdit(tag),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        const SizedBox(width: 10),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                            size: 18,
                                          ),
                                          onPressed: () async {
                                            try {
                                              await libraryProvider.deleteTag(
                                                tag.id,
                                              );
                                              if (_editingTagId == tag.id)
                                                _resetForm();
                                            } catch (e) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text('删除失败: $e'),
                                                ),
                                              );
                                            }
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Close Button
                SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cfg.bgHover,
                      foregroundColor: cfg.textMain,
                      elevation: 0,
                      side: BorderSide(color: cfg.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('关闭'),
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
