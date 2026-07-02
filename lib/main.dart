import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/features/layout/main_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  
  // Initialize library path for Rust backend
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UIThemeProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),
      ],
      child: const AetheriaApp(),
    ),
  );

  // Start the background audio server AFTER runApp so it never blocks the UI.
  // The cpal-based Rust engine handles playback directly; this server is only
  // kept for legacy/fallback streaming and can start lazily.
  try {
    final port = await music.startAudioServer();
    debugPrint('Rust audio server running on port $port');
  } catch (e) {
    debugPrint('Audio server start failed (non-fatal): $e');
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
