/// E-26-08e: Haptic feedback service.
///
/// Four levels mapped to user actions:
/// - success: message sent, action completed
/// - light: tap, selection
/// - medium: long-press, drag start
/// - heavy: destructive confirm, drop target
import 'package:flutter/services.dart';

class HapticService {
  /// Success haptic: message sent, save confirmed.
  static void success() => HapticFeedback.mediumImpact();

  /// Light haptic: tap, selection change.
  static void light() => HapticFeedback.selectionClick();

  /// Medium haptic: long-press, drag start.
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy haptic: destructive confirm, drop.
  static void heavy() => HapticFeedback.heavyImpact();
}
