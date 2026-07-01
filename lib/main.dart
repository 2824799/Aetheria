import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final directory = await getApplicationDocumentsDirectory();
  await music.initializeLibraryPath(path: directory.path);
  
  // Start the background local audio streaming server
  final port = await music.startAudioServer();
  print('Rust audio server running on port $port');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UIThemeProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()..audioServerPort = port),
        ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),
      ],
      child: const AetheriaApp(),
    ),
  );
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
