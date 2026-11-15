import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/features/library/ui/library_import.dart';
import 'package:aetheria/features/library/ui/settings/settings_library_tab.dart';
import 'package:aetheria/features/library/ui/song_list_summary.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart' show PreviewInfo;

import 'support/ui_test_fakes.dart';

const _playlists = [
  Playlist(id: 'pl-1', name: '我的最爱', createdAt: ''),
  Playlist(id: 'pl-2', name: 'ACG 精选', createdAt: ''),
];

const _previews = [
  PreviewInfo(
    filepath: '/music/01.flac',
    filename: '01.flac',
    title: '第一首',
    artist: '歌手A',
  ),
  PreviewInfo(
    filepath: '/music/02.mp3',
    filename: '02.mp3',
    title: '第二首',
    artist: '歌手B',
  ),
];

class _StubImportLibrary extends TestLibrary {
  _StubImportLibrary(this.nextReport);

  SongImportReport nextReport;
  String? receivedTargetPlaylistId;
  bool? receivedAddToActivePlaylist;

  @override
  Future<SongImportReport> importSongsWithReport(
    List<SongImportRequest> requests, {
    void Function(int done)? onProgress,
    String? targetPlaylistId,
    bool addToActivePlaylist = true,
  }) async {
    receivedTargetPlaylistId = targetPlaylistId;
    receivedAddToActivePlaylist = addToActivePlaylist;
    onProgress?.call(requests.length);
    return nextReport;
  }
}

void main() {
  testWidgets('folder preview defaults to active playlist and returns it', (
    tester,
  ) async {
    ImportPreviewSelection? selection;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                selection = await showAetherDialog<ImportPreviewSelection>(
                  context: context,
                  builder: (_) => const ImportFolderPreviewDialog(
                    previews: _previews,
                    playlists: _playlists,
                    initialPlaylistId: 'pl-2',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('添加到歌单'), findsOneWidget);
    expect(find.text('ACG 精选'), findsOneWidget);

    await tester.tap(find.text('导入 2 首'));
    await tester.pumpAndSettle();

    expect(selection, isNotNull);
    expect(selection!.previews, hasLength(2));
    expect(selection!.targetPlaylistId, 'pl-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder preview allows overriding target playlist or clearing', (
    tester,
  ) async {
    ImportPreviewSelection? selection;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                selection = await showAetherDialog<ImportPreviewSelection>(
                  context: context,
                  builder: (_) => const ImportFolderPreviewDialog(
                    previews: _previews,
                    playlists: _playlists,
                    initialPlaylistId: 'pl-1',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的最爱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不添加到歌单（仅全部歌曲）'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入 2 首'));
    await tester.pumpAndSettle();

    expect(selection?.targetPlaylistId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder preview hides playlist selector when no playlists exist', (
    tester,
  ) async {
    ImportPreviewSelection? selection;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                selection = await showAetherDialog<ImportPreviewSelection>(
                  context: context,
                  builder: (_) =>
                      const ImportFolderPreviewDialog(previews: _previews),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('添加到歌单'), findsNothing);
    await tester.tap(find.text('导入 2 首'));
    await tester.pumpAndSettle();

    expect(selection?.targetPlaylistId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder preview fits narrow mobile viewport without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _host(
          const ImportFolderPreviewDialog(
            previews: _previews,
            playlists: _playlists,
            initialPlaylistId: 'pl-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加到歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile settings library tab shows active playlist import note', (
    tester,
  ) async {
    final library = TestLibrary()
      ..playlists = _playlists
      ..activePlaylistId = 'pl-2';

    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: ListenableBuilder(
            listenable: library,
            builder: (context, _) => SettingsLibraryTab(
              cfg: AppThemeConfig.dark,
              libraryProvider: library,
              isDesktop: false,
              onChangeLibraryPath: () {},
              onImportFiles: () {},
              onImportFolder: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('当前选中歌单「ACG 精选」'), findsOneWidget);

    library.setActivePlaylist(null);
    await tester.pump();
    expect(find.textContaining('当前为“全部歌曲”'), findsOneWidget);
  });

  testWidgets('empty playlist state mentions direct import', (tester) async {
    final library = TestLibrary()
      ..songs = [testSong('1')]
      ..playlists = _playlists
      ..activePlaylistId = 'pl-1';

    await tester.pumpWidget(_host(SongListEmptyState(library: library)));
    expect(find.textContaining('导入歌曲'), findsOneWidget);

    await tester.pumpWidget(
      _host(SongListEmptyState(library: library, touch: true)),
    );
    expect(find.textContaining('设置 › 音乐库'), findsOneWidget);
  });

  testWidgets('import progress toast names target playlist when added', (
    tester,
  ) async {
    final library = _StubImportLibrary((
      failures: const [],
      importedCount: 2,
      targetPlaylist: _playlists.first,
      playlistError: null,
    ));
    addTearDown(library.dispose);

    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => importWithProgressForTest(
                context,
                library,
                const [
                  (filepath: '/a.mp3', title: null, artist: null),
                  (filepath: '/b.mp3', title: null, artist: null),
                ],
                targetPlaylistId: 'pl-1',
              ),
              child: const Text('Run'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(library.receivedTargetPlaylistId, 'pl-1');
    expect(library.receivedAddToActivePlaylist, isFalse);
    expect(find.text('已导入 2 首歌曲，并添加到歌单「我的最爱」'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: buildAetheriaThemeData(AppThemeConfig.dark),
  home: Scaffold(body: child),
);
