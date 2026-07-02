import 'package:flutter/services.dart';

class NativeAudioHelper {
  static const _channel = MethodChannel('com.aetheria.app/notification');

  static Future<void> showNotification(String title, String artist, bool isPlaying) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
      });
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
    await _channel.invokeMethod('saveToDownloads', {
      'filePath': filePath,
      'fileName': fileName,
    });
  }
}
