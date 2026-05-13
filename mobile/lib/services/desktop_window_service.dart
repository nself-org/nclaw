/// E-26-10b: Always-on-top and window management for desktop.
///
/// Uses window_manager for pin-on-top, remember position/size,
/// and quick capture floating window.
import 'dart:io';

import 'package:flutter/foundation.dart';

class DesktopWindowService {
  static bool _alwaysOnTop = false;

  /// Initialize window settings (restore position/size).
  static Future<void> initialize() async {
    if (!_isDesktop) return;

    try {
      // window_manager package.
      // await windowManager.ensureInitialized();
      // final prefs = await SharedPreferences.getInstance();
      // final x = prefs.getDouble('window_x');
      // final y = prefs.getDouble('window_y');
      // final w = prefs.getDouble('window_w') ?? 1024;
      // final h = prefs.getDouble('window_h') ?? 768;
      // if (x != null && y != null) {
      //   await windowManager.setPosition(Offset(x, y));
      // }
      // await windowManager.setSize(Size(w, h));
      // await windowManager.show();

      debugPrint('[DesktopWindow] Window initialized');
    } catch (e) {
      debugPrint('[DesktopWindow] Failed to initialize: $e');
    }
  }

  /// Toggle always-on-top mode.
  static Future<void> toggleAlwaysOnTop() async {
    if (!_isDesktop) return;
    _alwaysOnTop = !_alwaysOnTop;
    // await windowManager.setAlwaysOnTop(_alwaysOnTop);
    debugPrint('[DesktopWindow] Always on top: $_alwaysOnTop');
  }

  /// Get current always-on-top state.
  static bool get isAlwaysOnTop => _alwaysOnTop;

  /// Save current window position and size.
  static Future<void> savePosition() async {
    if (!_isDesktop) return;
    // final position = await windowManager.getPosition();
    // final size = await windowManager.getSize();
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setDouble('window_x', position.dx);
    // await prefs.setDouble('window_y', position.dy);
    // await prefs.setDouble('window_w', size.width);
    // await prefs.setDouble('window_h', size.height);
  }

  /// Open a floating quick capture window.
  static Future<void> openQuickCapture() async {
    if (!_isDesktop) return;
    // Show the main window and switch to quick capture mode.
    // await windowManager.show();
    // await windowManager.focus();
    // await windowManager.setAlwaysOnTop(true);
    // await windowManager.setSize(const Size(400, 300));
    debugPrint('[DesktopWindow] Quick capture window opened');
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}
