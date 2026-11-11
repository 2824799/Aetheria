import 'package:flutter/painting.dart';

import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/src/rust/models/song.dart';

const _losslessFormats = {'flac', 'wav', 'alac', 'ape'};

String audioQualityText(AudioVersion? version) {
  if (version == null) {
    return '无源';
  }

  final sampleRate = version.sampleRate;
  final bitDepth = version.bitDepth;
  final bitrate = version.bitrate;
  final loudness = version.loudness;
  final text = [
    if (sampleRate != null)
      '${(sampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '')}k',
    if (bitDepth != null) '${bitDepth}b',
    if (bitrate != null) '${(bitrate / 1000).round()}kbps',
    if (loudness != null) '${loudness.toStringAsFixed(1)}dB',
  ].join('/');
  return text.isEmpty ? '未知' : text;
}

/// Badge colour for a version's quality tier, taken from the theme's semantic
/// status colours so it stays legible on every palette.
Color audioQualityColor(AudioVersion? version, AppThemeConfig cfg) {
  if (version == null) {
    return cfg.textSecondary;
  }
  if (_losslessFormats.contains(version.format?.toLowerCase())) {
    return cfg.success;
  }

  final bitrate = version.bitrate;
  if (bitrate == null) {
    return cfg.textSecondary;
  }
  final kbps = (bitrate / 1000).round();
  if (kbps < 192) return cfg.danger;
  if (kbps < 256) return cfg.warning;
  if (kbps >= 320) return cfg.success;
  return cfg.info;
}
