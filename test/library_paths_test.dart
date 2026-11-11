import 'package:aetheria/core/utils/library_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed paths use only the last filename component', () {
    for (final stored in [
      'files/track.flac',
      'track.flac',
      '../../track.flac',
      '/outside/track.flac',
      r'C:\outside\track.flac',
    ]) {
      expect(managedAudioPath('/library', stored), '/library/files/track.flac');
      expect(
        managedCoverPath('/library', stored),
        '/library/covers/track.flac',
      );
    }
  });

  test('invalid filenames cannot become drive paths or data streams', () {
    for (final stored in [
      '',
      '.',
      '..',
      'files/',
      'files/..',
      'C:outside.wav',
      'files/C:outside.wav',
      'track.wav:stream',
      'bad\u0000.wav',
    ]) {
      expect(managedFileName(stored), isNull, reason: stored);
      expect(managedAudioPath('/library', stored), isNull, reason: stored);
      expect(managedCoverPath('/library', stored), isNull, reason: stored);
    }
  });

  test('paths require an initialized library root', () {
    expect(managedAudioPath('', 'track.wav'), isNull);
    expect(managedCoverPath('  ', 'cover.jpg'), isNull);
  });

  test('Windows library roots and filenames retain Unicode', () {
    expect(
      managedAudioPath(r'C:\音乐库', r'files\晴天.flac'),
      'C:/音乐库/files/晴天.flac',
    );
    expect(managedFileName(r'C:\Music\晴天.flac'), '晴天.flac');
  });
}
