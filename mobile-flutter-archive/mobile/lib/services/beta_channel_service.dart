/// F-28-10/11: Beta program configuration.
///
/// Manages opt-in beta channel for desktop auto-updates.
/// iOS/Android beta via TestFlight/Play Internal Test (handled by CI).
/// Desktop: switches Sparkle/Squirrel/AppImage feed URLs to beta variants.
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BetaChannelService {
  static const _storage = FlutterSecureStorage();
  static const _betaKey = 'beta_program_opted_in';

  /// Stable feed URLs.
  static const _stableFeedUrls = {
    'macos_appcast': 'https://downloads.nself.org/claw/macos/appcast.xml',
    'windows_releases': 'https://downloads.nself.org/claw/windows/RELEASES',
    'linux_latest': 'https://downloads.nself.org/claw/linux/latest.json',
  };

  /// Beta feed URLs.
  static const _betaFeedUrls = {
    'macos_appcast': 'https://downloads.nself.org/claw/beta/macos/appcast-beta.xml',
    'windows_releases': 'https://downloads.nself.org/claw/beta/windows/RELEASES-beta',
    'linux_latest': 'https://downloads.nself.org/claw/beta/linux/latest.json',
  };

  /// Check if user has opted into the beta program.
  static Future<bool> isBetaOptedIn() async {
    final value = await _storage.read(key: _betaKey);
    return value == 'true';
  }

  /// Toggle beta program opt-in.
  static Future<void> setBetaOptIn(bool optIn) async {
    await _storage.write(key: _betaKey, value: optIn ? 'true' : 'false');
    debugPrint('[BetaChannel] Beta program ${optIn ? "enabled" : "disabled"}');
  }

  /// Get the appropriate feed URL for the current platform.
  static Future<String?> getFeedUrl(String platform) async {
    final isBeta = await isBetaOptedIn();
    final urls = isBeta ? _betaFeedUrls : _stableFeedUrls;
    return urls[platform];
  }

  /// Get all feed URLs based on current opt-in status.
  static Future<Map<String, String>> getAllFeedUrls() async {
    final isBeta = await isBetaOptedIn();
    return isBeta ? _betaFeedUrls : _stableFeedUrls;
  }
}
