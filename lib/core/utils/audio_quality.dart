import 'package:flutter/material.dart';

import 'package:aetheria/src/rust/models/song.dart';

String audioQualityText(AudioVersion? version) {
  if (version == null) {
    return '无源';
  }

  final frequency = version.sampleRate != null
      ? '${(version.sampleRate! / 1000).toStringAsFixed(1).replaceAll('.0', '')}k'
      : '';
  final bitDepth = version.bitDepth != null ? '${version.bitDepth}b' : '';
  final bitrate = version.bitrate != null
      ? '${(version.bitrate! / 1000).round()}kbps'
      : '';
  final loudness = version.loudness != null
      ? '${version.loudness!.toStringAsFixed(1)}dB'
      : '';
  final text = [
    frequency,
    bitDepth,
    bitrate,
    loudness,
  ].where((item) => item.isNotEmpty).join('/');
  return text.isEmpty ? '未知' : text;
}

Color audioQualityColor(AudioVersion? version, Color fallback) {
  if (version == null) {
    return fallback;
  }
  final format = version.format?.toLowerCase() ?? '';
  final bitrateKbps = version.bitrate == null
      ? null
      : (version.bitrate! / 1000).round();
  final isLossless =
      format == 'flac' ||
      format == 'wav' ||
      format == 'alac' ||
      format == 'ape';
  final isHiRes =
      (version.bitDepth != null && version.bitDepth! > 16) ||
      (version.sampleRate != null && version.sampleRate! >= 48000);

  if (isLossless || isHiRes || (bitrateKbps != null && bitrateKbps >= 320)) {
    return const Color(0xFF10B981);
  }
  if (bitrateKbps != null && bitrateKbps < 192) {
    return Colors.redAccent;
  }
  if (bitrateKbps != null && bitrateKbps < 256) {
    return const Color(0xFFF59E0B);
  }
  if (bitrateKbps != null) {
    return const Color(0xFF3B82F6);
  }
  return fallback;
}
