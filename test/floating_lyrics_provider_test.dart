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
}
