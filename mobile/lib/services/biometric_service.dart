/// E-26-08d: Biometric unlock service.
///
/// Uses flutter_secure_storage + local_auth for Face ID / Touch ID / fingerprint
/// authentication on app resume.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static const _platform = MethodChannel('com.nself.nclaw/biometric');
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'nclaw_biometric_enabled';

  /// Check if biometric authentication is available on this device.
  static Future<bool> isAvailable() async {
    try {
      final result = await _platform.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // local_auth not installed; biometric not available.
      return false;
    }
  }

  /// Authenticate the user with biometrics.
  static Future<bool> authenticate({
    String reason = 'Authenticate to access nClaw',
  }) async {
    try {
      final result = await _platform.invokeMethod<bool>('authenticate', {
        'reason': reason,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true; // No biometric plugin; allow access.
    }
  }

  /// Check if biometric lock is enabled by the user.
  static Future<bool> isEnabled() async {
    final value = await _storage.read(key: _enabledKey);
    return value == 'true';
  }

  /// Enable or disable biometric lock.
  static Future<void> setEnabled(bool enabled) async {
    await _storage.write(key: _enabledKey, value: enabled.toString());
  }
}
