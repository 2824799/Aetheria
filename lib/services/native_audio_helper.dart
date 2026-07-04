import 'package:flutter/services.dart';

class NativeAudioHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.aetheria.app/notification',
  );
  static Future<void> Function(String)? _notificationActionHandler;
  static bool _isMethodHandlerBound = false;

  static void setNotificationActionHandler(
    Future<void> Function(String) handler,
  ) {
    _notificationActionHandler = handler;
    if (_isMethodHandlerBound) {
      return;
    }
    _isMethodHandlerBound = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'notificationAction') {
        return;
      }

      final dynamic arguments = call.arguments;
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
}
