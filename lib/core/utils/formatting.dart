import 'dart:ui';

/// Parses a `#RRGGBB` tag colour. Returns [fallback] when [hex] is missing or
/// malformed, so a bad value in the database can never break a build method.
Color parseTagColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length != 6) return fallback;
  final rgb = int.tryParse(clean, radix: 16);
  return rgb == null ? fallback : Color(0xFF000000 | rgb);
}

/// Formats a byte count as `12.3 MB`.
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  var index = 0;
  var size = bytes.toDouble();
  while (size >= 1024 && index < suffixes.length - 1) {
    size /= 1024;
    index++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[index]}';
}

/// Formats a length in seconds as `m:ss`.
String formatDurationSeconds(num seconds) {
  final total = seconds.isFinite ? seconds.round() : 0;
  final clamped = total < 0 ? 0 : total;
  return '${clamped ~/ 60}:${(clamped % 60).toString().padLeft(2, '0')}';
}
