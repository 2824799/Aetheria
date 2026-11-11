import 'dart:ui';

import 'package:aetheria/core/utils/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fallback = Color(0xFF123456);

  group('parseTagColor', () {
    test('parses #RRGGBB with and without the hash', () {
      expect(parseTagColor('#3b82f6', fallback), const Color(0xFF3B82F6));
      expect(parseTagColor('3B82F6', fallback), const Color(0xFF3B82F6));
    });

    test('falls back instead of throwing on bad input', () {
      expect(parseTagColor(null, fallback), fallback);
      expect(parseTagColor('', fallback), fallback);
      expect(parseTagColor('#fff', fallback), fallback);
      expect(parseTagColor('#zzzzzz', fallback), fallback);
    });
  });

  test('formatFileSize picks a readable unit', () {
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(512), '512.0 B');
    expect(formatFileSize(1536), '1.5 KB');
    expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
  });

  test('formatDurationSeconds never shows 60 seconds', () {
    expect(formatDurationSeconds(0), '0:00');
    expect(formatDurationSeconds(65.2), '1:05');
    expect(formatDurationSeconds(59.6), '1:00');
    expect(formatDurationSeconds(double.nan), '0:00');
  });
}
