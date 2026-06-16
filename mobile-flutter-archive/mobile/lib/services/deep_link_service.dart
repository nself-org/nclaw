import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parameters parsed from an incoming `nclaw://pair?server=...&code=...` deep link
/// or a scanned QR code. Consumed once by [_PairWithCodeTabState].
class PairParams {
  final String serverUrl;
  final String code;

  const PairParams({required this.serverUrl, required this.code});
}

/// Holds the most recently received pair params. Set by [NClawApp] when a deep
/// link arrives; cleared by [_PairWithCodeTabState] after consuming it.
final pendingPairProvider = StateProvider<PairParams?>((ref) => null);
