import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/sidebar/ui/sidebar.dart';
import 'package:aetheria/features/library/ui/main_content.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/features/player/ui/play_bar.dart';
import 'package:aetheria/features/player/ui/detail_pane.dart';
import 'package:aetheria/features/layout/mobile_layout.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _desktopDesignWidth = 1280;

  late AnimationController _drawerController;
  late Animation<Offset> _drawerSlide;
  late Animation<double> _scrimFade;
  final SongTableController _songTableController = SongTableController();
  String? _handledSyncRequestId;
  bool _imeDismissedInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drawerController = AnimationController(
      duration: AetherMotion.panel,
      reverseDuration: AetherMotion.exit(AetherMotion.panel),
      vsync: this,
    );
    final curved = CurvedAnimation(
      parent: _drawerController,
      curve: AetherMotion.outQuart,
      reverseCurve: AetherMotion.out,
    );
    _drawerSlide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curved);
    _scrimFade = curved;
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
    WidgetsBinding.instance.removeObserver(this);
    _drawerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _dismissKeyboard();
      _imeDismissedInBackground = true;
    } else if (state == AppLifecycleState.resumed &&
        _imeDismissedInBackground) {
      _imeDismissedInBackground = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dismissKeyboard();
        }
      });
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _revealPlayingSong() async {
    final audioProvider = context.read<AudioPlayerProvider>();
    final playingSong = audioProvider.playingSong;
    if (playingSong == null) {
      return;
    }

    _dismissKeyboard();
    if (audioProvider.isDetailOpen) {
      audioProvider.setDetailOpen(false);
    }

    final revealed = await _songTableController.revealSong(playingSong.id);
    if (!mounted || revealed) {
      return;
    }

    showAetherToast(
      context,
      message: '当前歌曲不在这个歌单或筛选结果中',
      kind: AetherToastKind.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 768;
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.read<AudioPlayerProvider>();
    final isDetailOpen = context.select<AudioPlayerProvider, bool>(
      (provider) => provider.isDetailOpen,
    );
    context.watch<UIThemeProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final cfg = context.tokens;

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

    // Keep drawer motion in sync with reduced-motion preference.
    _drawerController.duration = AetherMotion.duration(
      context,
      AetherMotion.panel,
    );
    _drawerController.reverseDuration = AetherMotion.exitOf(
      context,
      AetherMotion.panel,
    );

    if (isDetailOpen) {
      if (_drawerController.status != AnimationStatus.forward &&
          _drawerController.status != AnimationStatus.completed) {
        if (AetherMotion.reduce(context)) {
          _drawerController.value = 1;
        } else {
          _drawerController.forward();
        }
      }
    } else {
      if (_drawerController.status != AnimationStatus.reverse &&
          _drawerController.status != AnimationStatus.dismissed) {
        if (AetherMotion.reduce(context)) {
          _drawerController.value = 0;
        } else {
          _drawerController.reverse();
        }
      }
    }

    if (libraryProvider.isLoading && libraryProvider.songs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(gradient: cfg.bgApp),
          child: const AetherLoading(message: '加载音乐库…'),
        ),
      );
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
        body: _buildDesktopBody(audioProvider, cfg),
      ),
    );
  }

  Widget _buildDesktopShell(
    BuildContext context,
    AudioPlayerProvider audioProvider,
    AppThemeConfig cfg,
  ) {
    final size = MediaQuery.sizeOf(context);
    final showDrawer =
        _drawerController.value > 0.0 || audioProvider.isDetailOpen;

    return Stack(
      children: [
        Positioned(
          top: size.height * 0.1,
          left: size.width * 0.2,
          child: AmbientGlow(color: cfg.accent, opacity: cfg.ambientOpacity),
        ),
        Positioned(
          bottom: size.height * 0.2,
          right: size.width * 0.15,
          child: AmbientGlow(
            color: cfg.accentHover,
            opacity: cfg.ambientOpacity,
          ),
        ),
        Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Sidebar(width: 220),
                  Expanded(
                    child: Stack(
                      children: [
                        MainContent(songTableController: _songTableController),
                        if (showDrawer)
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _drawerController,
                              builder: (context, _) {
                                return IgnorePointer(
                                  ignoring:
                                      _drawerController.status ==
                                      AnimationStatus.dismissed,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTap: () {
                                            _dismissKeyboard();
                                            audioProvider.setDetailOpen(false);
                                          },
                                          child: FadeTransition(
                                            opacity: _scrimFade,
                                            child: ColoredBox(
                                              color: cfg.scrim.withValues(
                                                alpha: 0.28,
                                              ),
                                            ),
                                          ),
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
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PlayBar(height: 84, onPlayingSongLongPress: _revealPlayingSong),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopBody(
    AudioPlayerProvider audioProvider,
    AppThemeConfig cfg,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final media = MediaQuery.of(context);

        if (width >= _desktopDesignWidth || width <= 0 || height <= 0) {
          return _buildDesktopShell(context, audioProvider, cfg);
        }

        final scale = width / _desktopDesignWidth;
        final designHeight = height / scale;

        return SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _desktopDesignWidth,
                height: designHeight,
                child: MediaQuery(
                  data: media.copyWith(
                    size: Size(_desktopDesignWidth, designHeight),
                    textScaler: media.textScaler.clamp(
                      minScaleFactor: 0.9,
                      maxScaleFactor: 1.1,
                    ),
                  ),
                  child: Builder(
                    builder: (scaledContext) =>
                        _buildDesktopShell(scaledContext, audioProvider, cfg),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showIncomingSyncDialog(IncomingSyncRequest request) async {
    final syncProvider = context.read<SyncProvider>();
    final approved = await showAetherDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return AetherDialog(
          title: '同步请求',
          content: Text(
            '${request.deviceName} 请求从本设备同步音乐库。\n\n'
            '同意后，对方会拉取本机曲库数据和 files 文件夹内容。主题、悬浮歌词、音频处理等本机设置不会同步。',
            style: AetherType.bodyStyle(tokens.textSecondary),
          ),
          actions: [
            AetherButton.ghost(
              label: '拒绝',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            AetherButton.primary(
              label: '同意同步',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
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
  final double opacity;
  const AmbientGlow({super.key, required this.color, this.opacity = 0.12});

  @override
  Widget build(BuildContext context) {
    final glow = color.withValues(alpha: opacity);
    return IgnorePointer(
      child: Container(
        width: 450,
        height: 450,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: glow,
          boxShadow: [
            BoxShadow(color: glow, blurRadius: 120, spreadRadius: 60),
          ],
        ),
      ),
    );
  }
}
