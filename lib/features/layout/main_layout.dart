import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/features/sidebar/ui/sidebar.dart';
import 'package:aetheria/features/library/ui/main_content.dart';
import 'package:aetheria/features/player/ui/play_bar.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin {
  late AnimationController _drawerController;
  late Animation<Offset> _drawerSlide;
  String? _handledSyncRequestId;

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _drawerSlide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _drawerController,
            curve: Curves.easeOutQuart,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final libraryProvider = context.read<LibraryProvider>();
      await libraryProvider.loadLibrary();
      if (!mounted) {
        return;
      }
      await context.read<SyncProvider>().start(libraryProvider);
      if (!mounted) {
        return;
      }
      await context.read<AudioPlayerProvider>().restorePlaybackState(
        libraryProvider.songs,
        libraryProvider.libraryPath,
        audioServerPort: libraryProvider.audioServerPort,
      );
    });
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final cfg = themeProvider.currentTheme;

    final incomingRequest = syncProvider.incomingRequest;
    if (incomingRequest != null &&
        incomingRequest.id != _handledSyncRequestId) {
      _handledSyncRequestId = incomingRequest.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showIncomingSyncDialog(incomingRequest);
        }
      });
    }

    if (audioProvider.isDetailOpen) {
      _drawerController.forward();
    } else {
      _drawerController.reverse();
    }

    if (libraryProvider.isLoading && libraryProvider.songs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(gradient: cfg.bgApp),
        child: const MobileLayout(),
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: cfg.bgApp),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Ambient Glows
            Positioned(
              top: MediaQuery.of(context).size.height * 0.1,
              left: MediaQuery.of(context).size.width * 0.2,
              child: AmbientGlow(color: cfg.accent),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.2,
              right: MediaQuery.of(context).size.width * 0.15,
              child: AmbientGlow(color: cfg.accentHover),
            ),

            // Main Grid
            Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Sidebar(width: 200),
                      Expanded(
                        child: Stack(
                          children: [
                            const MainContent(),
                            if (_drawerController.value > 0.0 ||
                                audioProvider.isDetailOpen)
                              Positioned.fill(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: () =>
                                            audioProvider.setDetailOpen(false),
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      width: 380,
                                      child: SlideTransition(
                                        position: _drawerSlide,
                                        child: const DetailPane(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const PlayBar(height: 90),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIncomingSyncDialog(IncomingSyncRequest request) async {
    final syncProvider = context.read<SyncProvider>();
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('同步请求'),
        content: Text(
          '${request.deviceName} 请求从本设备同步音乐库。'
          '\n\n同意后，对方会拉取本机曲库数据和 files 文件夹内容。主题、悬浮歌词、音频处理等本机设置不会同步。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('拒绝'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意同步'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    if (approved == true) {
      await syncProvider.approveIncomingRequest(request.id);
    } else {
      await syncProvider.denyIncomingRequest(request.id);
    }
  }
}

class AmbientGlow extends StatelessWidget {
  final Color color;
  const AmbientGlow({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 450,
      height: 450,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 120,
            spreadRadius: 60,
          ),
        ],
      ),
    );
  }
}
