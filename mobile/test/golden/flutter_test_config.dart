// flutter_test_config.dart
// Scoped to test/golden/ — applies to golden_test.dart only.
//
// Problem: golden baselines are generated on macOS but CI runs on ubuntu-latest.
// Flutter font rendering differs between platforms, producing ~0.40% pixel diffs
// that fail strict golden comparisons.
//
// Fix: allow up to 1% pixel difference. Diffs above that still fail (real regressions).
// The 1% threshold is well above observed CI drift (0.40%) but well below any
// meaningful UI change (which would typically cause >5% diff).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator as LocalFileComparator;
  // comparator.basedir is already a directory URI (e.g. .../test/golden/).
  // LocalFileComparator(testUri) does dirname(testUri) internally, so passing
  // a directory URI strips one level up to .../test/ — wrong.
  // Fix: resolve a filename inside basedir so dirname lands back in basedir.
  goldenFileComparator = _ThresholdComparator(
    comparator.basedir.resolve('flutter_test_config.dart'),
  );
  await testMain();
}

/// Golden comparator that tolerates up to [_maxDiffPercent] pixel difference.
///
/// Cross-platform rendering (macOS vs Linux) causes minor subpixel differences
/// in font kerning and anti-aliasing. This threshold absorbs that noise while
/// still catching real visual regressions.
class _ThresholdComparator extends LocalFileComparator {
  _ThresholdComparator(super.testUri);

  /// Maximum acceptable pixel diff as a fraction of total pixels (0–1).
  /// 0.01 = 1%. Observed CI-vs-macOS drift is ~0.004 (0.40%).
  static const double _maxDiffPercent = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) return true;
    final diff = result.diffPercent;
    if (diff <= _maxDiffPercent) {
      debugPrint(
        '[golden] ${golden.pathSegments.last}: '
        '${(diff * 100).toStringAsFixed(2)}% diff — within '
        '${(_maxDiffPercent * 100).toStringAsFixed(0)}% threshold (pass)',
      );
      return true;
    }
    return false;
  }
}
