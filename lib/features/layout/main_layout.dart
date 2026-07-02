import 'package:flutter/material.dart';
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

class _MainLayoutState extends State<MainLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    if (libraryProvider.isLoading && libraryProvider.songs.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                            if (audioProvider.isDetailOpen)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                width: 360,
                                child: const DetailPane(),
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
