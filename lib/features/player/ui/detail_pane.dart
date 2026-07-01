import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

class DetailPane extends StatelessWidget {
  const DetailPane({super.key});

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _linkNewVersion(BuildContext context, Song song, LibraryProvider provider) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      await provider.importAudioVersionForSong(song.id, path);

      Navigator.of(context).pop(); // pop progress indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('成功关联新音源版本')),
      );
    } catch (e) {
      Navigator.of(context).pop(); // pop loader if failed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('关联失败: $e')),
      );
    }
  }

  Future<void> _exportVersion(BuildContext context, AudioVersion version) async {
    try {
      String? destPath = await FilePicker.platform.saveFile(
        fileName: version.originalName,
        dialogTitle: '选择保存音频的位置',
      );

      if (destPath == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      await music.exportAudioFile(versionId: version.id, destPath: destPath);

      Navigator.of(context).pop(); // pop progress indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音频文件导出还原成功！')),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;
    
    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == audioProvider.activeSong?.id,
      orElse: () => audioProvider.activeSong ?? Song(
        id: '',
        title: '',
        rating: 0,
        createdAt: '',
        versions: [],
        tags: [],
      ),
    );

    if (song.id.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: cfg.bgPanel,
        border: Border(left: BorderSide(color: cfg.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 30,
            offset: const Offset(-10, 0),
          )
        ],
      ),
      child: Column(
        children: [
          // Close button
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(Icons.close, color: cfg.textSub),
              onPressed: () => audioProvider.setDetailOpen(false),
            ),
          ),
          
          // Header (Artwork Cover placeholder, Title, Artist)
          Container(
            width: 130,
            height: 130,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.06), cfg.border],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: cfg.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Icon(Icons.music_note, size: 48, color: cfg.accent),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              song.title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cfg.textMain, fontFamily: 'Outfit'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            song.artist ?? '未知歌手',
            style: TextStyle(fontSize: 12, color: cfg.textSub, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 16),
          
          // Tabs (Versions, Tags, Lyrics)
          Row(
            children: [
              _buildTab(context, '音源版本', 'versions', audioProvider, cfg),
              _buildTab(context, '标签管理', 'tags', audioProvider, cfg),
              _buildTab(context, '歌词', 'lyrics', audioProvider, cfg),
            ],
          ),
          Divider(height: 1, color: cfg.border),
          
          // Content Area
          Expanded(
            child: _buildContent(context, song, audioProvider, libraryProvider, cfg),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    String title,
    String tabId,
    AudioPlayerProvider provider,
    AppThemeConfig cfg,
  ) {
    final isActive = provider.activeTab == tabId;
    return Expanded(
      child: InkWell(
        onTap: () => provider.setActiveTab(tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? cfg.accent : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? cfg.textMain : cfg.textSub,
              fontFamily: 'Outfit',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Song song,
    AudioPlayerProvider audioProvider,
    LibraryProvider libraryProvider,
    AppThemeConfig cfg,
  ) {
    if (audioProvider.activeTab == 'versions') {
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: song.versions.length,
              itemBuilder: (context, index) {
                final v = song.versions[index];
                
                final durationMin = (v.duration / 60).floor();
                final durationSec = (v.duration % 60).round().toString().padLeft(2, '0');
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.white.withOpacity(0.04),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: cfg.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Filename
                        Text(
                          v.originalName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cfg.textMain, fontFamily: 'Outfit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        
                        // Technical specs
                        Text(
                          '${v.format?.toUpperCase() ?? "未知"} | ${(v.bitrate ?? 0) ~/ 1000}kbps | ${v.sampleRate != null ? (v.sampleRate! / 1000).toStringAsFixed(1) : "未知"}kHz | $durationMin:$durationSec | ${_formatFileSize(v.fileSize.toInt())}',
                          style: TextStyle(fontSize: 10, color: cfg.textSub, fontFamily: 'Outfit'),
                        ),
                        const SizedBox(height: 10),
                        
                        // Checkbox for Enable & Radio for Primary
                        Row(
                          children: [
                            // Enabled Checkbox
                            InkWell(
                              onTap: () async {
                                await libraryProvider.updateVersionStatus(v.id, !v.isEnabled, v.isPrimary);
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    v.isEnabled ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 16,
                                    color: v.isEnabled ? cfg.accent : cfg.textSub,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('启用版本', style: TextStyle(fontSize: 11, color: cfg.textMain)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Primary Radio (can only set true, cannot set false manually as something must be primary)
                            InkWell(
                              onTap: () async {
                                if (!v.isPrimary) {
                                  await libraryProvider.updateVersionStatus(v.id, true, true);
                                }
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    v.isPrimary ? Icons.radio_button_checked : Icons.radio_button_off,
                                    size: 16,
                                    color: v.isPrimary ? cfg.accent : cfg.textSub,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('设为主音源', style: TextStyle(fontSize: 11, color: cfg.textMain)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        
                        // Export and Delete buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: () => _exportVersion(context, v),
                              icon: Icon(Icons.download, size: 13, color: cfg.textSub),
                              label: Text('导出物理文件', style: TextStyle(fontSize: 11, color: cfg.textSub)),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            if (song.versions.length > 1)
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await libraryProvider.deleteAudioVersion(v.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('音频版本已删除')),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('删除失败: $e')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.delete, size: 13, color: Colors.redAccent),
                                label: const Text('删除版本', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Link New Version button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () => _linkNewVersion(context, song, libraryProvider),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('关联新的音源版本', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cfg.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    if (audioProvider.activeTab == 'tags') {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: libraryProvider.tags.length,
        itemBuilder: (context, index) {
          final tag = libraryProvider.tags[index];
          final isBound = song.tags.any((t) => t.id == tag.id);
          final tagColor = tag.color != null ? _parseHexColor(tag.color!, cfg.textSub) : cfg.textSub;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () async {
                await libraryProvider.tagSong(song.id, tag.id, !isBound);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cfg.border.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBound ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 16,
                      color: isBound ? cfg.accent : cfg.textSub,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '[${tag.category ?? "自定义"}] ${tag.name}',
                      style: TextStyle(color: tagColor, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    
    if (audioProvider.activeTab == 'lyrics') {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          song.lyrics ?? '暂无歌词',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cfg.textMain,
            height: 1.8,
            fontSize: 13,
            fontFamily: 'Outfit',
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}
