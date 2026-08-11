import 'package:flutter/services.dart';

class NativeAudioHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.aetheria.app/notification',
  );
  static Future<void> Function(String)? _notificationActionHandler;
  static Future<void> Function(Map<String, dynamic>)?
  _floatingLyricEventHandler;
  static Future<void> Function()? _audioRouteChangedHandler;
  static bool _isMethodHandlerBound = false;

  static void setNotificationActionHandler(
    Future<void> Function(String) handler,
  ) {
    _notificationActionHandler = handler;
    _ensureMethodCallHandlerBound();
  }

  static void _ensureMethodCallHandlerBound() {
    if (_isMethodHandlerBound) {
      return;
    }
    _isMethodHandlerBound = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      final dynamic arguments = call.arguments;
      if (call.method == 'audioRouteChanged') {
        await _audioRouteChangedHandler?.call();
        return;
      }
      if (call.method == 'floatingLyricsEvent') {
        final handler = _floatingLyricEventHandler;
        if (handler != null && arguments is Map) {
          await handler(Map<String, dynamic>.from(arguments));
        }
        return;
      }
      if (call.method != 'notificationAction') {
        return;
      }

      String action = '';
      if (arguments is Map && arguments['action'] != null) {
        action = arguments['action'].toString();
      }

      final handler = _notificationActionHandler;
      if (handler != null && action.isNotEmpty) {
        await handler(action);
      }
    });
  }

  static void setFloatingLyricEventHandler(
    Future<void> Function(Map<String, dynamic>) handler,
  ) {
    _floatingLyricEventHandler = handler;
    _ensureMethodCallHandlerBound();
  }

  static void setAudioRouteChangedHandler(Future<void> Function() handler) {
    _audioRouteChangedHandler = handler;
    _ensureMethodCallHandlerBound();
  }

  static Future<void> showNotification(Map<String, dynamic> payload) async {
    try {
      await _channel.invokeMethod('showNotification', payload);
    } catch (_) {}
  }

  static Future<void> hideNotification() async {
    try {
      await _channel.invokeMethod('hideNotification');
    } catch (_) {}
  }

  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  static Future<void> saveToDownloads(String filePath, String fileName) async {
    await _channel.invokeMethod('saveToDownloads', <String, dynamic>{
      'filePath': filePath,
      'fileName': fileName,
    });
  }

  static Future<void> acquireMulticastLock() async {
    try {
      await _channel.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  static Future<void> releaseMulticastLock() async {
    try {
      await _channel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
  }

  static Future<String?> getDeviceName() async {
    try {
      return await _channel.invokeMethod<String>('getDeviceName');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> canDrawOverlays() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<bool> initializeSuperLyric() async {
    try {
      return await _channel.invokeMethod<bool>('initializeSuperLyric') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> publishSuperLyric(Map<String, dynamic> payload) async {
    try {
      return await _channel.invokeMethod<bool>('publishSuperLyric', payload) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopSuperLyric(Map<String, dynamic> payload) async {
    try {
      return await _channel.invokeMethod<bool>('stopSuperLyric', payload) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> disposeSuperLyric() async {
    try {
      await _channel.invokeMethod('disposeSuperLyric');
    } catch (_) {}
  }

  static Future<void> showFloatingLyrics() async {
    try {
      await _channel.invokeMethod('showFloatingLyrics');
    } catch (_) {}
  }

  static Future<void> hideFloatingLyrics() async {
    try {
      await _channel.invokeMethod('hideFloatingLyrics');
    } catch (_) {}
  }

  static Future<void> updateFloatingLyricsStyle(
    Map<String, dynamic> payload,
  ) async {
    try {
      await _channel.invokeMethod('updateFloatingLyricsStyle', payload);
    } catch (_) {}
  }

  static Future<void> updateFloatingLyrics(Map<String, dynamic> payload) async {
    try {
      await _channel.invokeMethod('updateFloatingLyrics', payload);
    } catch (_) {}
  }
}
