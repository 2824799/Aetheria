import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';

class TagManagerModal extends StatefulWidget {
  const TagManagerModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => const TagManagerModal(),
    );
  }

  @override
  State<TagManagerModal> createState() => _TagManagerModalState();
}

class _TagManagerModalState extends State<TagManagerModal> {
  final TextEditingController _tagNameController = TextEditingController();
  String _selectedCategory = '自定义';
  String _selectedColor = '#3b82f6';

  final List<String> _presetColors = [
    '#ef4444',
    '#3b82f6',
    '#f43f5e',
    '#10b981',
    '#f59e0b',
    '#ec4899',
    '#84cc16',
    '#64748b',
    '#8b5cf6',
    '#06b6d4',
    '#eab308',
  ];

  Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return Colors.grey;
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
                        '新建自定义标签',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _tagNameController,
                                style: TextStyle(color: cfg.textMain, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '标签名, 如: 抒情',
                                  hintStyle: TextStyle(color: cfg.textSub.withOpacity(0.5)),
                                  filled: true,
                                  fillColor: Colors.black.withOpacity(0.06),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: cfg.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategory,
                                dropdownColor: cfg.bgPanel,
                                style: TextStyle(color: cfg.textMain, fontSize: 13),
                                items: ['流派', '语言', '情绪', '场景', '自定义']
                                    .map((cat) => DropdownMenuItem(
                                          value: cat,
                                          child: Text(cat),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedCategory = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final name = _tagNameController.text.trim();
                              if (name.isEmpty) return;
                              try {
                                await libraryProvider.addTag(name, _selectedColor, _selectedCategory);
                                _tagNameController.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('创建标签成功')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('创建失败: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('创建', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cfg.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Color Picker Grid
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presetColors.map((colorHex) {
                          final color = _parseHexColor(colorHex);
                          final isSelected = _selectedColor == colorHex;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedColor = colorHex;
                              });
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected ? cfg.textMain : Colors.transparent,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tag List Manager
                Text(
                  '标签列表',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cfg.textSub),
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
                              style: TextStyle(color: cfg.textSub, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: libraryProvider.tags.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: cfg.border.withOpacity(0.5)),
                            itemBuilder: (context, index) {
                              final tag = libraryProvider.tags[index];
                              final tagColor = tag.color != null ? _parseHexColor(tag.color!) : cfg.textMain;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                      onPressed: () async {
                                        try {
                                          await libraryProvider.deleteTag(tag.id);
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('删除失败: $e')),
                                          );
                                        }
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  @override
  void dispose() {
    _tagNameController.dispose();
    super.dispose();
  }
}
