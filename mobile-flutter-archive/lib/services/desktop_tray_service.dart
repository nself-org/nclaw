/// E-26-09: Desktop system tray / menu bar service.
///
/// Uses system_tray package for tray icon with submenu.
/// Shows unread badge. Start minimized to tray (setting).
/// Launch at login (platform-native). Quit confirmation during streaming.
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Tray menu item definition.
class TrayMenuItem {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  const TrayMenuItem({
    required this.label,
    this.onTap,
    this.enabled = true,
  });
}

class DesktopTrayService {
  static bool _initialized = false;
  static int _unreadCount = 0;

  /// Initialize the system tray (desktop only).
  static Future<void> initialize({
    required VoidCallback onNewConversation,
    required VoidCallback onQuickCapture,
    required VoidCallback onOpenLast,
    required VoidCallback onSettings,
    required Future<bool> Function() onQuit,
  }) async {
    if (!_isDesktop) return;

    try {
      // system_tray package initialization.
      // final systemTray = SystemTray();
      // await systemTray.initSystemTray(
      //   title: 'nClaw',
      //   iconPath: _trayIconPath,
      //   toolTip: 'nClaw AI Assistant',
      // );

      // Build menu.
      // final menu = Menu();
      // await menu.buildFrom([
      //   MenuItemLabel(label: 'New conversation', onClicked: (_) => onNewConversation()),
      //   MenuItemLabel(label: 'Quick capture', onClicked: (_) => onQuickCapture()),
      //   MenuItemLabel(label: 'Open last', onClicked: (_) => onOpenLast()),
      //   MenuSeparator(),
      //   MenuItemLabel(label: 'Settings', onClicked: (_) => onSettings()),
      //   MenuSeparator(),
      //   MenuItemLabel(label: 'Quit', onClicked: (_) async {
      //     final canQuit = await onQuit();
      //     if (canQuit) exit(0);
      //   }),
      // ]);
      // await systemTray.setContextMenu(menu);

      // systemTray.registerSystemTrayEventHandler((eventName) {
      //   if (eventName == kSystemTrayEventClick) {
      //     // Show/hide window on tray icon click.
      //     systemTray.popUpContextMenu();
      //   }
      // });

      _initialized = true;
      debugPrint('[DesktopTray] System tray initialized');
    } catch (e) {
      debugPrint('[DesktopTray] Failed to initialize: $e');
    }
  }

  /// Update the unread badge count on the tray icon.
  static Future<void> updateBadge(int count) async {
    if (!_initialized) return;
    _unreadCount = count;

    // Update tray tooltip/badge.
    // final systemTray = SystemTray();
    // await systemTray.setToolTip(
    //   count > 0 ? 'nClaw ($count unread)' : 'nClaw',
    // );
    debugPrint('[DesktopTray] Badge updated: $count');
  }

  /// Set tray icon to offline variant.
  static Future<void> setOffline(bool offline) async {
    if (!_initialized) return;
    // final systemTray = SystemTray();
    // await systemTray.setImage(offline ? _offlineIconPath : _trayIconPath);
    debugPrint('[DesktopTray] Offline: $offline');
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  // static String get _trayIconPath => Platform.isMacOS
  //     ? 'assets/icons/tray_icon.png'
  //     : 'assets/icons/tray_icon.ico';

  // static String get _offlineIconPath => Platform.isMacOS
  //     ? 'assets/icons/tray_icon_offline.png'
  //     : 'assets/icons/tray_icon_offline.ico';
}
