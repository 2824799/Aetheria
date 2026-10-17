import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'FloatingLyricsProvider recognizes edge negative coordinates as saved position',
    () {
      final provider = FloatingLyricsProvider();

      expect(provider.hasSavedWindowPosition, isFalse);

      provider.windowX = -15.0;
      provider.windowY = 120.0;
      expect(provider.hasSavedWindowPosition, isTrue);

      provider.windowX = FloatingLyricsProvider.unsetWindowPos;
      provider.windowY = FloatingLyricsProvider.unsetWindowPos;
      expect(provider.hasSavedWindowPosition, isFalse);
    },
  );

  test(
    'notifyLyricUpdated increments lyricRevision and notifies listeners',
    () {
      final provider = FloatingLyricsProvider();
      int notifiedCount = 0;
      provider.addListener(() {
        notifiedCount++;
      });

      expect(provider.lyricRevision, equals(0));
      provider.notifyLyricUpdated();
      expect(provider.lyricRevision, equals(1));
      expect(notifiedCount, equals(1));

      provider.notifyLyricUpdated();
      expect(provider.lyricRevision, equals(2));
      expect(notifiedCount, equals(2));
    },
  );

  test('SuperLyric output is optional and disabled by default', () async {
    final provider = FloatingLyricsProvider();
    await provider.load();

    expect(provider.superLyricEnabled, isFalse);

    await provider.setSuperLyricEnabled(true);
    expect(provider.superLyricEnabled, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('aetheria-floating-lyrics-super-lyric-enabled'),
      isTrue,
    );
  });

  test('paused opacity supports endpoints and survives reload', () async {
    final provider = FloatingLyricsProvider();
    await provider.load();
    final signature = provider.styleSignature;

    await provider.setPauseOpacity(0);
    expect(provider.stylePayload()['pauseOpacity'], 0);
    expect(provider.styleSignature, isNot(signature));
    expect(provider.opacity, 0.95);
    final restored = FloatingLyricsProvider();
    await restored.load();
    expect(restored.pauseOpacity, 0);

    await provider.setPauseOpacity(0.47);
    await restored.load();
    expect(restored.pauseOpacity, 0.47);
    await provider.setPauseOpacity(1);
    await restored.load();
    expect(restored.pauseOpacity, 1);
    expect(restored.opacity, 0.95);

    await provider.setPauseOpacity(-1);
    expect(provider.pauseOpacity, 0);
    await provider.setPauseOpacity(2);
    expect(provider.pauseOpacity, 1);
    provider.dispose();
    restored.dispose();
  });

  for (final legacyFade in [true, false]) {
    test('migrates the old pause fade switch ($legacyFade)', () async {
      SharedPreferences.setMockInitialValues({
        'aetheria-floating-lyrics-opacity': 0.8,
        'aetheria-floating-lyrics-pause-fade': legacyFade,
      });
      final provider = FloatingLyricsProvider();
      await provider.load();
      final expected = legacyFade ? 0.8 * 0.22 : 0.8;
      expect(provider.pauseOpacity, closeTo(expected, 0.000001));

      // Once migrated, changing playback opacity cannot change pause opacity.
      await provider.setOpacity(0.5);
      await provider.load();
      expect(provider.pauseOpacity, closeTo(expected, 0.000001));
      provider.dispose();
    });
  }
}
