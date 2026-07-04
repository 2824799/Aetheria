import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
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

class _MainLayoutState extends State<MainLayout> with SingleTickerProviderStateMixin {
  late AnimationController _drawerController;
  late Animation<double> _drawerFade;
  late Animation<Offset> _drawerSlide;

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      duration: const Duration(milliseconds: 360),
      vsync: this,
    );
    _drawerFade = CurvedAnimation(
      parent: _drawerController,
      curve: Curves.easeOutCubic,
    );
    _drawerSlide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _drawerController,
      curve: Curves.easeOutCubic,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().loadLibrary();
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
    final cfg = themeProvider.currentTheme;

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
                            if (_drawerController.value > 0.0 || audioProvider.isDetailOpen)
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: _drawerFade,
                                  builder: (context, child) {
                                    final progress = _drawerFade.value;
                                    return Opacity(
                                      opacity: progress,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: GestureDetector(
                                              onTap: () => audioProvider.setDetailOpen(false),
                                              child: BackdropFilter(
                                                filter: ImageFilter.blur(
                                                  sigmaX: 18 * progress,
                                                  sigmaY: 18 * progress,
                                                ),
                                                child: Container(color: Colors.black.withOpacity(0.18)),
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
                const PlayBar(height: 90),
              ],
            ),
          ],
        ),
      ),
    );
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
