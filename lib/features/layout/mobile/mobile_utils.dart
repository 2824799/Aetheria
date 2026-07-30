import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';

Color mobileParseHexColor(String hex, Color defaultColor) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return defaultColor;
}

String mobileFormatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  var i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

AudioVersion? mobileDisplayVersionForSong(
  Song song,
  AudioPlayerProvider audioProvider,
) {
  final playingVersion = audioProvider.playingVersion;
  if (audioProvider.playingSong?.id == song.id && playingVersion != null) {
    return playingVersion;
  }
  for (final version in song.versions) {
    if (version.isPrimary) return version;
  }
  return song.versions.isNotEmpty ? song.versions.first : null;
}

class MobileLrcBadge extends StatelessWidget {
  final AppThemeConfig cfg;
  const MobileLrcBadge({super.key, required this.cfg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.sm - 1,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: cfg.accentMuted,
        borderRadius: BorderRadius.circular(AetherRadius.xs),
        border: Border.all(color: cfg.accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        'LRC',
        style: AetherType.captionStyle(cfg.accent).copyWith(
          fontWeight: FontWeight.w800,
          fontSize: AetherType.caption - 1,
          letterSpacing: 0,
          height: 1.1,
        ),
      ),
    );
  }
}
