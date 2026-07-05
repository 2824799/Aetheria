import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.songCount,
    required this.versionCount,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final int songCount;
  final int versionCount;
  final DateTime lastSeen;

  String get endpoint => '$address:$port';
}

class IncomingSyncRequest {
  const IncomingSyncRequest({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.createdAt,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String address;
  final DateTime createdAt;
}

class _SyncSession {
  const _SyncSession({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

class _RemoteFileInfo {
  const _RemoteFileInfo({required this.path, required this.size, this.md5});

  final String path;
  final int size;
  final String? md5;

  factory _RemoteFileInfo.fromJson(Map<String, dynamic> json) {
    return _RemoteFileInfo(
      path: json['path']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      md5: json['md5']?.toString(),
    );
  }
}

class SyncProvider extends ChangeNotifier {
  static const int _discoveryPort = 43871;
  static const String _announceType = 'aetheria-sync-announcement';
  static const String _deviceIdKey = 'aetheria-sync-device-id';
  static const Duration _deviceTtl = Duration(seconds: 45);
  static const Duration _requestTimeout = Duration(seconds: 90);
  static const Duration _sessionTtl = Duration(minutes: 5);

  final Map<String, SyncDevice> _devices = {};
  final Map<String, Completer<bool>> _pendingRequestCompleters = {};
  final Map<String, _SyncSession> _sessions = {};
  final HttpClient _client = HttpClient();

  LibraryProvider? _libraryProvider;
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  String? _deviceId;
  String? _deviceName;

  bool isRunning = false;
  bool isDiscovering = false;
  bool isSyncing = false;
  double? progress;
  String statusMessage = '局域网同步服务未启动';
  String? errorMessage;
  IncomingSyncRequest? incomingRequest;

  SyncProvider() {
    _client.findProxy = (_) => 'DIRECT';
  }

  List<SyncDevice> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  String get localDeviceName => _deviceName ?? '本机设备';

  int? get localPort => _server?.port;

  Future<void> start(LibraryProvider libraryProvider) async {
    _libraryProvider = libraryProvider;
    if (isRunning) {
      return;
    }

    if (Platform.isAndroid) {
      await NativeAudioHelper.acquireMulticastLock();
    }
    _deviceId = await _loadOrCreateDeviceId();
    _deviceName = await _resolveDeviceName();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      unawaited(_serveHttp(_server!));

      try {
        _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _discoveryPort,
          reuseAddress: true,
        );
        _udpSocket!.broadcastEnabled = true;
        _udpSocket!.listen(_handleUdpEvent);
        isDiscovering = true;
      } catch (e) {
        isDiscovering = false;
        errorMessage = '设备发现启动失败: $e';
      }

      isRunning = true;
      statusMessage = isDiscovering ? '局域网同步服务已启动' : '同步服务已启动，但设备发现不可用';
      _announceTimer?.cancel();
      _announceTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(announceNow()),
      );
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _removeStaleDevices(),
      );
      await announceNow();
    } catch (e) {
      errorMessage = '同步服务启动失败: $e';
      statusMessage = '局域网同步服务启动失败';
    }

    notifyListeners();
  }

  Future<void> announceNow() async {
    await _sendAnnouncement();
  }

  Future<void> _sendAnnouncement({InternetAddress? targetAddress}) async {
    final socket = _udpSocket;
    final server = _server;
    final libraryProvider = _libraryProvider;
    if (socket == null || server == null || libraryProvider == null) {
      return;
    }

    final payload = jsonEncode({
      'type': _announceType,
      'version': 1,
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'port': server.port,
      'songCount': libraryProvider.songs.length,
      'versionCount': libraryProvider.songs.fold<int>(
        0,
        (sum, song) => sum + song.versions.length,
      ),
      'reply': targetAddress != null,
    });
    final data = utf8.encode(payload);
    if (targetAddress != null) {
      socket.send(data, targetAddress, _discoveryPort);
      return;
    }
    final targets = await _broadcastTargets();
    for (final target in targets) {
      socket.send(data, target, _discoveryPort);
    }
  }

  void clearDevices() {
    _devices.clear();
    notifyListeners();
    unawaited(announceNow());
  }

  Future<void> pullFromDevice({
    required SyncDevice device,
    required LibraryProvider libraryProvider,
    required AudioPlayerProvider audioProvider,
  }) async {
    if (isSyncing) {
      return;
    }

    isSyncing = true;
    progress = null;
    errorMessage = null;
    statusMessage = '正在请求 ${device.name} 授权...';
    notifyListeners();

    Directory? tempDir;
    Directory? backupDir;
    try {
      final token = await _requestRemoteApproval(device);
      progress = null;
      statusMessage = '正在读取远端文件清单...';
      notifyListeners();

      final manifest = await _fetchManifest(device, token);
      final remoteFiles = (manifest['files'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(_RemoteFileInfo.fromJson)
          .where((file) => _isSafeLibraryFilePath(file.path))
          .toList();

      tempDir = await _createTempDir(libraryProvider.libraryPath);
      final tempDb = File(_joinPath(tempDir.path, ['database.db']));
      progress = null;
      statusMessage = '正在下载远端数据库...';
      notifyListeners();
      await _downloadToFile(
        Uri.http(device.endpoint, '/sync/database'),
        tempDb,
        token,
      );
      final remoteDatabase = manifest['database'] is Map<String, dynamic>
          ? manifest['database'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final remoteDatabaseMd5 = remoteDatabase['md5']?.toString();
      if (remoteDatabaseMd5 != null && remoteDatabaseMd5.isNotEmpty) {
        final downloadedDbHash = await _fileMd5(tempDb);
        if (downloadedDbHash != remoteDatabaseMd5) {
          throw Exception('数据库校验失败');
        }
      }

      final plan = await _buildFileSyncPlan(
        libraryProvider.libraryPath,
        remoteFiles,
      );

      var completed = 0;
      final totalSteps = plan.downloads.length + 2;
      void updateProgress(String message) {
        statusMessage = message;
        progress = totalSteps <= 0 ? null : completed / totalSteps;
        notifyListeners();
      }

      for (final file in plan.downloads) {
        updateProgress('正在下载 ${file.path.split('/').last}...');
        final destination = File(_joinPath(tempDir.path, file.path.split('/')));
        await destination.parent.create(recursive: true);
        await _downloadToFile(
          Uri.http(device.endpoint, '/sync/file', {'path': file.path}),
          destination,
          token,
        );
        final remoteMd5 = file.md5;
        if (remoteMd5 != null && remoteMd5.isNotEmpty) {
          final downloadedHash = await _fileMd5(destination);
          if (downloadedHash != remoteMd5) {
            throw Exception('文件校验失败: ${file.path}');
          }
        }
        completed++;
      }

      updateProgress('正在暂停播放并准备覆盖本地库...');
      await audioProvider.stopForLibrarySync();
      backupDir = await _createBackupDir(libraryProvider.libraryPath);
      await _applyMirrorSync(
        libraryProvider.libraryPath,
        tempDb,
        tempDir,
        backupDir,
        plan,
      );
      completed++;

      updateProgress('正在重新加载音乐库...');
      await music.initializeLibraryPath(path: libraryProvider.libraryPath);
      await libraryProvider.loadLibrary();
      await announceNow();
      completed++;

      progress = 1;
      statusMessage = '同步完成，已以 ${device.name} 的音乐库为准';
    } catch (e) {
      errorMessage = e.toString();
      statusMessage = '同步失败';
      rethrow;
    } finally {
      isSyncing = false;
      final dirToDelete = tempDir;
      if (dirToDelete != null) {
        unawaited(_deleteTempDir(dirToDelete));
      }
      notifyListeners();
    }
  }

  Future<void> _deleteTempDir(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> approveIncomingRequest(String requestId) async {
    final completer = _pendingRequestCompleters.remove(requestId);
    if (incomingRequest?.id == requestId) {
      incomingRequest = null;
    }
    completer?.complete(true);
    notifyListeners();
  }

  Future<void> denyIncomingRequest(String requestId) async {
    final completer = _pendingRequestCompleters.remove(requestId);
    if (incomingRequest?.id == requestId) {
      incomingRequest = null;
    }
    completer?.complete(false);
    notifyListeners();
  }

  Future<String> _requestRemoteApproval(SyncDevice device) async {
    final requestId = _newId();
    final request = await _client.postUrl(
      Uri.http(device.endpoint, '/sync/request'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'requestId': requestId,
        'deviceId': _deviceId,
        'deviceName': _deviceName,
      }),
    );
    final response = await request.close().timeout(_requestTimeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('远端拒绝同步请求: $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['approved'] != true) {
      throw Exception('远端未同意同步请求');
    }
    final token = json['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('远端授权无效');
    }
    return token;
  }

  Future<Map<String, dynamic>> _fetchManifest(
    SyncDevice device,
    String token,
  ) async {
    final request = await _client.getUrl(
      Uri.http(device.endpoint, '/sync/manifest'),
    );
    request.headers.set('X-Aetheria-Sync-Token', token);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('读取远端清单失败: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> _downloadToFile(Uri uri, File destination, String token) async {
    final request = await _client.getUrl(uri);
    request.headers.set('X-Aetheria-Sync-Token', token);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final body = await utf8.decoder.bind(response).join();
      throw Exception('下载失败: $body');
    }
    await destination.parent.create(recursive: true);
    final sink = destination.openWrite();
    await response.pipe(sink);
  }

  Future<_FileSyncPlan> _buildFileSyncPlan(
    String libraryPath,
    List<_RemoteFileInfo> remoteFiles,
  ) async {
    final filesDir = Directory(_joinPath(libraryPath, ['files']));
    await filesDir.create(recursive: true);
    final localFiles = await _listLibraryFiles(filesDir, libraryPath);
    final remoteByPath = {for (final file in remoteFiles) file.path: file};
    final downloads = <_RemoteFileInfo>[];
    final removeOrReplace = <String>{};

    for (final local in localFiles) {
      final remote = remoteByPath[local];
      if (remote == null) {
        removeOrReplace.add(local);
        continue;
      }

      final localFile = File(_resolveLibraryRelativePath(libraryPath, local));
      final stat = await localFile.stat();
      if (stat.size != remote.size) {
        removeOrReplace.add(local);
        downloads.add(remote);
        continue;
      }

      final remoteMd5 = remote.md5;
      if (remoteMd5 != null && remoteMd5.isNotEmpty) {
        final hash = await _fileMd5(localFile);
        if (hash != remoteMd5) {
          removeOrReplace.add(local);
          downloads.add(remote);
        }
      }
    }

    for (final remote in remoteFiles) {
      if (!localFiles.contains(remote.path)) {
        downloads.add(remote);
      }
    }

    return _FileSyncPlan(
      remoteFiles: remoteFiles,
      downloads: downloads,
      removeOrReplace: removeOrReplace,
    );
  }

  Future<void> _applyMirrorSync(
    String libraryPath,
    File tempDb,
    Directory tempDir,
    Directory backupDir,
    _FileSyncPlan plan,
  ) async {
    final dbFile = File(_joinPath(libraryPath, ['database.db']));
    await backupDir.create(recursive: true);

    if (await dbFile.exists()) {
      await dbFile.copy(_joinPath(backupDir.path, ['database.db']));
    }

    final sourcePaths = plan.remoteFiles.map((file) => file.path).toSet();
    final filesDir = Directory(_joinPath(libraryPath, ['files']));
    await filesDir.create(recursive: true);
    final localFiles = await _listLibraryFiles(filesDir, libraryPath);
    final pathsToRemove = <String>{
      ...plan.removeOrReplace,
      ...localFiles.where((path) => !sourcePaths.contains(path)),
    };

    for (final relPath in pathsToRemove) {
      final localPath = _resolveLibraryRelativePath(libraryPath, relPath);
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        continue;
      }
      final backupPath = _resolveLibraryRelativePath(backupDir.path, relPath);
      await File(backupPath).parent.create(recursive: true);
      await _moveFile(localFile, File(backupPath));
    }

    for (final remote in plan.remoteFiles) {
      final destination = File(
        _resolveLibraryRelativePath(libraryPath, remote.path),
      );
      if (await destination.exists()) {
        continue;
      }
      final tempFile = File(
        _resolveLibraryRelativePath(tempDir.path, remote.path),
      );
      if (!await tempFile.exists()) {
        throw Exception('同步临时文件缺失: ${remote.path}');
      }
      await destination.parent.create(recursive: true);
      await tempFile.copy(destination.path);
    }

    await tempDb.copy(dbFile.path);
  }

  Future<Directory> _createTempDir(String libraryPath) {
    final base = Directory(_joinPath(libraryPath, ['.sync_tmp']));
    return base.create(recursive: true).then((_) => base.createTemp('pull_'));
  }

  Future<Directory> _createBackupDir(String libraryPath) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    final dir = Directory(_joinPath(libraryPath, ['sync_backups', stamp]));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _serveHttp(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handleHttpRequest(request);
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(e.toString());
        await request.response.close();
      }
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    switch (request.uri.path) {
      case '/sync/request':
        await _handleSyncRequest(request);
        return;
      case '/sync/manifest':
        await _handleManifestRequest(request);
        return;
      case '/sync/database':
        await _handleDatabaseRequest(request);
        return;
      case '/sync/file':
        await _handleFileRequest(request);
        return;
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('not found');
        await request.response.close();
    }
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final requestId = json['requestId']?.toString() ?? _newId();
    final completer = Completer<bool>();
    _pendingRequestCompleters[requestId] = completer;
    incomingRequest = IncomingSyncRequest(
      id: requestId,
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '未知设备',
      address: request.connectionInfo?.remoteAddress.address ?? '',
      createdAt: DateTime.now(),
    );
    notifyListeners();

    final approved = await completer.future
        .timeout(_requestTimeout, onTimeout: () => false)
        .whenComplete(() {
          _pendingRequestCompleters.remove(requestId);
          if (incomingRequest?.id == requestId) {
            incomingRequest = null;
            notifyListeners();
          }
        });

    request.response.headers.contentType = ContentType.json;
    if (!approved) {
      request.response.write(jsonEncode({'approved': false}));
      await request.response.close();
      return;
    }

    final token = _newId();
    _sessions[token] = _SyncSession(
      token: token,
      expiresAt: DateTime.now().add(_sessionTtl),
    );
    request.response.write(
      jsonEncode({
        'approved': true,
        'token': token,
        'expiresAt': _sessions[token]!.expiresAt.toIso8601String(),
      }),
    );
    await request.response.close();
  }

  Future<void> _handleManifestRequest(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('unauthorized');
      await request.response.close();
      return;
    }

    final libraryProvider = _libraryProvider;
    if (libraryProvider == null || libraryProvider.libraryPath.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('library not ready');
      await request.response.close();
      return;
    }

    final dbFile = File(
      _joinPath(libraryProvider.libraryPath, ['database.db']),
    );
    final filesDir = Directory(
      _joinPath(libraryProvider.libraryPath, ['files']),
    );
    final filePaths = await _listLibraryFiles(
      filesDir,
      libraryProvider.libraryPath,
    );
    final files = <Map<String, dynamic>>[];
    for (final relPath in filePaths) {
      final file = File(
        _resolveLibraryRelativePath(libraryProvider.libraryPath, relPath),
      );
      final stat = await file.stat();
      files.add({'path': relPath, 'size': stat.size});
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'database': {
          'size': await dbFile.exists() ? await dbFile.length() : 0,
          'md5': await dbFile.exists() ? await _fileMd5(dbFile) : '',
        },
        'files': files,
      }),
    );
    await request.response.close();
  }

  Future<void> _handleDatabaseRequest(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('unauthorized');
      await request.response.close();
      return;
    }
    final libraryProvider = _libraryProvider;
    if (libraryProvider == null) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('library not ready');
      await request.response.close();
      return;
    }
    final dbFile = File(
      _joinPath(libraryProvider.libraryPath, ['database.db']),
    );
    if (!await dbFile.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('database not found');
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.binary;
    request.response.contentLength = await dbFile.length();
    await request.response.addStream(dbFile.openRead());
    await request.response.close();
  }

  Future<void> _handleFileRequest(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('unauthorized');
      await request.response.close();
      return;
    }
    final libraryProvider = _libraryProvider;
    final relPath = request.uri.queryParameters['path'] ?? '';
    if (libraryProvider == null || !_isSafeLibraryFilePath(relPath)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('invalid path');
      await request.response.close();
      return;
    }
    final file = File(
      _resolveLibraryRelativePath(libraryProvider.libraryPath, relPath),
    );
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('file not found');
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.binary;
    request.response.contentLength = await file.length();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  bool _isAuthorized(HttpRequest request) {
    final token = request.headers.value('X-Aetheria-Sync-Token');
    if (token == null) {
      return false;
    }
    final session = _sessions[token];
    if (session == null || DateTime.now().isAfter(session.expiresAt)) {
      _sessions.remove(token);
      return false;
    }
    return true;
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final datagram = _udpSocket?.receive();
    if (datagram == null) {
      return;
    }
    try {
      final json =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (json['type'] != _announceType || json['deviceId'] == _deviceId) {
        return;
      }
      final port = (json['port'] as num?)?.toInt();
      final deviceId = json['deviceId']?.toString();
      if (port == null || deviceId == null || deviceId.isEmpty) {
        return;
      }
      _devices[deviceId] = SyncDevice(
        id: deviceId,
        name: _sanitizeDeviceName(json['deviceName']?.toString()),
        address: datagram.address.address,
        port: port,
        songCount: (json['songCount'] as num?)?.toInt() ?? 0,
        versionCount: (json['versionCount'] as num?)?.toInt() ?? 0,
        lastSeen: DateTime.now(),
      );
      if (json['reply'] != true) {
        unawaited(_sendAnnouncement(targetAddress: datagram.address));
      }
      notifyListeners();
    } catch (_) {}
  }

  void _removeStaleDevices() {
    final now = DateTime.now();
    final staleIds = _devices.entries
        .where((entry) => now.difference(entry.value.lastSeen) > _deviceTtl)
        .map((entry) => entry.key)
        .toList();
    if (staleIds.isEmpty) {
      return;
    }
    for (final id in staleIds) {
      _devices.remove(id);
    }
    notifyListeners();
  }

  Future<String> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_deviceIdKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final value = _newId();
    await prefs.setString(_deviceIdKey, value);
    return value;
  }

  Future<String> _resolveDeviceName() async {
    if (Platform.isAndroid) {
      final nativeName = _sanitizeDeviceName(
        await NativeAudioHelper.getDeviceName(),
      );
      if (nativeName != '未知设备') {
        return nativeName;
      }
    }
    try {
      final hostname = Platform.localHostname;
      final sanitized = _sanitizeDeviceName(hostname);
      if (sanitized != '未知设备') {
        return sanitized;
      }
    } catch (_) {}
    if (Platform.isAndroid) {
      return 'Android 设备';
    }
    if (Platform.isWindows) {
      return 'Windows 电脑';
    }
    return 'Aetheria 设备';
  }

  String _sanitizeDeviceName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) {
      return '未知设备';
    }
    final lower = name.toLowerCase();
    if (lower == 'localhost' || lower == 'localhost.localdomain') {
      return '未知设备';
    }
    return name;
  }

  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {}
    return targets.map(InternetAddress.new).toList();
  }

  Future<List<String>> _listLibraryFiles(
    Directory filesDir,
    String libraryPath,
  ) async {
    if (!await filesDir.exists()) {
      return [];
    }
    final result = <String>[];
    await for (final entity in filesDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final normalizedLibrary = _normalizePath(libraryPath);
      final normalizedFile = _normalizePath(entity.path);
      if (!normalizedFile.startsWith('$normalizedLibrary/')) {
        continue;
      }
      final rel = normalizedFile.substring(normalizedLibrary.length + 1);
      if (_isSafeLibraryFilePath(rel)) {
        result.add(rel);
      }
    }
    result.sort();
    return result;
  }

  Future<String> _fileMd5(File file) async {
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _moveFile(File source, File destination) async {
    await destination.parent.create(recursive: true);
    try {
      await source.rename(destination.path);
    } catch (_) {
      await source.copy(destination.path);
      await source.delete();
    }
  }

  bool _isSafeLibraryFilePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (!normalized.startsWith('files/')) {
      return false;
    }
    if (normalized.contains('..') || normalized.contains('//')) {
      return false;
    }
    return normalized.split('/').every((part) => part.isNotEmpty);
  }

  String _resolveLibraryRelativePath(String root, String relPath) {
    final normalized = relPath.replaceAll('\\', '/');
    if (!_isSafeLibraryFilePath(normalized)) {
      throw ArgumentError('Invalid library path: $relPath');
    }
    return _joinPath(root, normalized.split('/'));
  }

  String _joinPath(String root, List<String> parts) {
    var current = root;
    for (final part in parts) {
      current = current.endsWith(Platform.pathSeparator)
          ? '$current$part'
          : '$current${Platform.pathSeparator}$part';
    }
    return current;
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/');
  }

  String _newId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$random';
  }

  @override
  void dispose() {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _server?.close(force: true);
    _client.close(force: true);
    if (Platform.isAndroid) {
      unawaited(NativeAudioHelper.releaseMulticastLock());
    }
    super.dispose();
  }
}

class _FileSyncPlan {
  const _FileSyncPlan({
    required this.remoteFiles,
    required this.downloads,
    required this.removeOrReplace,
  });

  final List<_RemoteFileInfo> remoteFiles;
  final List<_RemoteFileInfo> downloads;
  final Set<String> removeOrReplace;
}
