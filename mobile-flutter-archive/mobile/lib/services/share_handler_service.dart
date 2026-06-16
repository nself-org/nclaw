/// E-26-05: Platform channel bridge for share sheet data.
///
/// iOS: reads from App Groups UserDefaults (written by ShareExtension).
/// Android: reads from MethodChannel (ShareReceiverActivity).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedContent {
  final String content;
  final String? title;
  final String? mimeType;

  const SharedContent({
    required this.content,
    this.title,
    this.mimeType,
  });
}

class ShareHandlerService {
  static const _channel = MethodChannel('com.nself.nclaw/share');

  /// Check for pending shared content.
  /// Returns null if no content was shared.
  static Future<SharedContent?> getSharedContent() async {
    if (kIsWeb) return null;

    try {
      if (Platform.isAndroid) {
        final data = await _channel.invokeMethod<Map>('getSharedData');
        if (data != null) {
          return SharedContent(
            content: data['content'] as String? ?? '',
            title: data['title'] as String?,
            mimeType: data['mime_type'] as String?,
          );
        }
      } else if (Platform.isIOS) {
        // iOS reads from App Groups shared UserDefaults.
        final data =
            await _channel.invokeMethod<Map>('getSharedContent');
        if (data != null) {
          return SharedContent(
            content: data['content'] as String? ?? '',
            title: data['title'] as String?,
            mimeType: data['mime_type'] as String?,
          );
        }
      }
    } on PlatformException catch (e) {
      debugPrint('[ShareHandler] Error: $e');
    } on MissingPluginException {
      // Share plugin not available on this platform.
    }
    return null;
  }

  /// Clear the shared content after it has been processed.
  static Future<void> clearSharedContent() async {
    try {
      await _channel.invokeMethod('clearSharedContent');
    } catch (_) {}
  }
}
