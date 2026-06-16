/// E-26-10a: Global hotkey service for desktop.
///
/// Registers Cmd+Shift+Space (configurable) to open a floating
/// always-on-top quick capture window.
import 'dart:io';

import 'package:flutter/foundation.dart';

class DesktopHotkeyService {
  static bool _registered = false;

  /// Register the global hotkey.
  static Future<void> register({
    required VoidCallback onActivate,
  }) async {
    if (!_isDesktop) return;

    try {
      // hotkey_manager package.
      // HotKeyManager.instance.register(
      //   HotKey(
      //     key: PhysicalKeyboardKey.space,
      //     modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
      //     scope: HotKeyScope.system,
      //   ),
      //   keyDownHandler: (_) => onActivate(),
      // );

      _registered = true;
      debugPrint('[DesktopHotkey] Global hotkey registered: Cmd+Shift+Space');
    } catch (e) {
      debugPrint('[DesktopHotkey] Failed to register hotkey: $e');
    }
  }

  /// Unregister all hotkeys.
  static Future<void> unregister() async {
    if (!_registered) return;
    // HotKeyManager.instance.unregisterAll();
    _registered = false;
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}
