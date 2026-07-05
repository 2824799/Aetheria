import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;

  try {
    await RustLib.init();
  } catch (e, st) {
    initError = 'RustLib.init() failed: $e\n$st';
    debugPrint(initError);
  }

  if (initError == null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('aetheria-library-path');
      String libPath;
      if (savedPath != null && savedPath.isNotEmpty) {
        libPath = savedPath;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        libPath = directory.path;
      }
      await music.initializeLibraryPath(path: libPath);
    } catch (e, st) {
      initError = 'initializeLibraryPath() failed: $e\n$st';
      debugPrint(initError);
    }
  }

  // ALWAYS run the app — even if Rust init failed, show something on screen
  // so we can diagnose the error instead of a blank white screen.
  runApp(
    initError != null
        ? MaterialApp(
            home: Scaffold(
              backgroundColor: const Color(0xFF1a1a2e),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aetheria 启动失败',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        initError,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => UIThemeProvider()),
              ChangeNotifierProvider(create: (_) => LibraryProvider()),
              ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),
              ChangeNotifierProvider(create: (_) => SyncProvider()),
            ],
            child: const AetheriaApp(),
          ),
  );

  // Start the background audio server AFTER runApp so it never blocks the UI.
  if (initError == null) {
    try {
      final port = await music.startAudioServer();
      debugPrint('Rust audio server running on port $port');
    } catch (e) {
      debugPrint('Audio server start failed (non-fatal): $e');
    }
  }
}

class AetheriaApp extends StatelessWidget {
  const AetheriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<UIThemeProvider>();
    return MaterialApp(
      title: 'Aetheria',
      theme: themeProvider.themeData,
      debugShowCheckedModeBanner: false,
      home: const MainLayout(),
    );
  }
}
