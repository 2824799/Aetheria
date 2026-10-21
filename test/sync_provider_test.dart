import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetheria/core/providers/sync_provider.dart';

void main() {
  group('SyncProvider Path Normalization & Listing', () {
    late SyncProvider provider;
    late Directory tempRoot;

    setUp(() async {
      provider = SyncProvider();
      tempRoot = await Directory.systemTemp.createTemp('aetheria_sync_test_');
    });

    tearDown(() async {
      provider.dispose();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('normalizePath trims multiple slashes and trailing slashes correctly', () {
      expect(provider.normalizePathForTesting('/home/user/music/'), '/home/user/music');
      expect(provider.normalizePathForTesting('/home/user/music///'), '/home/user/music');
      expect(provider.normalizePathForTesting(r'C:\Users\User\Music\'), 'C:/Users/User/Music');
      expect(provider.normalizePathForTesting('/'), '/');
    });

    test('listLibraryFiles correctly returns relative paths when libraryPath has trailing slash', () async {
      final libraryDir = Directory('${tempRoot.path}/my_library/');
      await libraryDir.create(recursive: true);

      final filesDir = Directory('${libraryDir.path}files/subdir');
      await filesDir.create(recursive: true);

      final song1 = File('${filesDir.path}/track1.flac');
      await song1.writeAsString('audio-data-1');

      final song2 = File('${libraryDir.path}files/track2.mp3');
      await song2.writeAsString('audio-data-2');

      final listWithTrailingSlash = await provider.listLibraryFilesForTesting(
        Directory('${libraryDir.path}files'),
        '${libraryDir.path}/',
      );
      expect(listWithTrailingSlash, containsAll([
        'files/subdir/track1.flac',
        'files/track2.mp3',
      ]));
      expect(listWithTrailingSlash.length, 2);

      final cleanLibraryPath = provider.normalizePathForTesting(libraryDir.path);
      final listWithoutTrailingSlash = await provider.listLibraryFilesForTesting(
        Directory('${libraryDir.path}files'),
        cleanLibraryPath,
      );
      expect(listWithoutTrailingSlash, containsAll([
        'files/subdir/track1.flac',
        'files/track2.mp3',
      ]));
      expect(listWithoutTrailingSlash.length, 2);
    });

    test('applyMirrorSync preserves existing files and installs new downloads', () async {
      final libraryDir = Directory('${tempRoot.path}/lib');
      final filesDir = Directory('${libraryDir.path}/files');
      await filesDir.create(recursive: true);

      // Existing local songs A and B
      final localA = File('${filesDir.path}/songA.flac');
      await localA.writeAsString('local-song-A');
      final localB = File('${filesDir.path}/songB.flac');
      await localB.writeAsString('local-song-B');

      // Local DB
      final localDb = File('${libraryDir.path}/database.db');
      await localDb.writeAsString('local-db-v1');

      // Sync artifacts: tempDir with new song C
      final tempDir = Directory('${tempRoot.path}/temp');
      final tempFilesDir = Directory('${tempDir.path}/files');
      await tempFilesDir.create(recursive: true);
      final downloadC = File('${tempFilesDir.path}/songC.flac');
      await downloadC.writeAsString('remote-song-C');

      final tempDb = File('${tempDir.path}/database.db');
      await tempDb.writeAsString('remote-db-v2');

      final backupDir = Directory('${tempRoot.path}/backup');

      // Execute applyMirrorSync with remoteFiles = [A, B, C], downloads = [C]
      await provider.applyMirrorSyncForTesting(
        libraryPath: libraryDir.path,
        tempDb: tempDb,
        tempDir: tempDir,
        backupDir: backupDir,
        remoteFilePaths: ['files/songA.flac', 'files/songB.flac', 'files/songC.flac'],
        downloadPaths: ['files/songC.flac'],
      );

      // Verify songA and songB are completely intact!
      expect(await localA.exists(), isTrue);
      expect(await localA.readAsString(), 'local-song-A');
      expect(await localB.exists(), isTrue);
      expect(await localB.readAsString(), 'local-song-B');

      // Verify songC was installed
      final installedC = File('${filesDir.path}/songC.flac');
      expect(await installedC.exists(), isTrue);
      expect(await installedC.readAsString(), 'remote-song-C');

      // Verify DB was updated
      expect(await localDb.readAsString(), 'remote-db-v2');

      // Verify DB backup exists
      final backupDb = File('${backupDir.path}/database.db');
      expect(await backupDb.exists(), isTrue);
      expect(await backupDb.readAsString(), 'local-db-v1');
    });

    test('applyMirrorSync removes only obsolete files not present in remote manifest', () async {
      final libraryDir = Directory('${tempRoot.path}/lib');
      final filesDir = Directory('${libraryDir.path}/files');
      await filesDir.create(recursive: true);

      // Local songs A, B and obsolete D
      final localA = File('${filesDir.path}/songA.flac');
      await localA.writeAsString('song-A');
      final localD = File('${filesDir.path}/songD.flac');
      await localD.writeAsString('song-D-to-remove');

      final localDb = File('${libraryDir.path}/database.db');
      await localDb.writeAsString('db-v1');

      final tempDir = Directory('${tempRoot.path}/temp');
      await tempDir.create(recursive: true);
      final tempDb = File('${tempDir.path}/database.db');
      await tempDb.writeAsString('db-v2');

      final backupDir = Directory('${tempRoot.path}/backup');

      // Remote manifest only contains A (D is removed)
      await provider.applyMirrorSyncForTesting(
        libraryPath: libraryDir.path,
        tempDb: tempDb,
        tempDir: tempDir,
        backupDir: backupDir,
        remoteFilePaths: ['files/songA.flac'],
        downloadPaths: [],
      );

      // A should remain
      expect(await localA.exists(), isTrue);
      // D should be removed from files/ but backed up in backupDir
      expect(await localD.exists(), isFalse);
      final backupD = File('${backupDir.path}/files/songD.flac');
      expect(await backupD.exists(), isTrue);
      expect(await backupD.readAsString(), 'song-D-to-remove');
    });

    test('buildFileSyncPlan correctly plans downloads and replacements using fast size comparison', () async {
      final libraryDir = Directory('${tempRoot.path}/fast_sync_lib');
      final filesDir = Directory('${libraryDir.path}/files');
      await filesDir.create(recursive: true);

      // Local files
      final localA = File('${filesDir.path}/songA.flac');
      await localA.writeAsBytes(List.filled(100, 1)); // 100 bytes, matching remote

      final localB = File('${filesDir.path}/songB.flac');
      await localB.writeAsBytes(List.filled(50, 2)); // 50 bytes, remote has 80 bytes (corrupted/changed)

      final localD = File('${filesDir.path}/songD.flac');
      await localD.writeAsBytes(List.filled(30, 4)); // 30 bytes, obsolete (not in remote)

      final plan = await provider.buildFileSyncPlanForTesting(
        libraryPath: libraryDir.path,
        remoteFiles: [
          (path: 'files/songA.flac', size: 100, md5: 'hashA'),
          (path: 'files/songB.flac', size: 80, md5: 'hashB'),
          (path: 'files/songC.flac', size: 200, md5: 'hashC'), // new file
        ],
      );

      // songA is identical: should NOT be in downloads, NOT in removeOrReplace
      expect(plan.downloads, isNot(contains('files/songA.flac')));
      expect(plan.removeOrReplace, isNot(contains('files/songA.flac')));

      // songB size mismatch: must be in downloads and in removeOrReplace
      expect(plan.downloads, contains('files/songB.flac'));
      expect(plan.removeOrReplace, contains('files/songB.flac'));

      // songC missing locally: must be in downloads
      expect(plan.downloads, contains('files/songC.flac'));

      // songD obsolete: must be in removeOrReplace
      expect(plan.removeOrReplace, contains('files/songD.flac'));
    });
  });
}
