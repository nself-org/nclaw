// Unit tests for BrandTheme, BrandColors, BrandSpacing, BrandRadii, and
// glassCardDecoration. Pure Dart — exercises the static tokens and the
// ThemeData factory.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/theme/brand_theme.dart';

void main() {
  group('BrandColors tokens', () {
    test('primary is nSelf indigo', () {
      expect(BrandColors.primary, const Color(0xFF6366F1));
    });

    test('all semantic colors are defined', () {
      expect(BrandColors.success, isNotNull);
      expect(BrandColors.warning, isNotNull);
      expect(BrandColors.error, isNotNull);
      expect(BrandColors.info, isNotNull);
    });

    test('neutrals are in descending lightness for readability', () {
      // textHigh should be lighter than textMedium, which > textLow, which >
      // textDisabled, on the dark surface.
      double b(Color c) => (c.r + c.g + c.b) / 3;
      expect(b(BrandColors.textHigh), greaterThan(b(BrandColors.textMedium)));
      expect(b(BrandColors.textMedium), greaterThan(b(BrandColors.textLow)));
      expect(b(BrandColors.textLow), greaterThan(b(BrandColors.textDisabled)));
    });
  });

  group('BrandSpacing', () {
    test('follows the 4-point grid', () {
      expect(BrandSpacing.xs, 4.0);
      expect(BrandSpacing.sm, 8.0);
      expect(BrandSpacing.md, 12.0);
      expect(BrandSpacing.lg, 16.0);
      expect(BrandSpacing.xl, 24.0);
      expect(BrandSpacing.xxl, 32.0);
    });
  });

  group('BrandRadii', () {
    test('has sensible defaults', () {
      expect(BrandRadii.sm, 6.0);
      expect(BrandRadii.md, 10.0);
      expect(BrandRadii.lg, 16.0);
      expect(BrandRadii.pill, 999.0);
    });
  });

  group('BrandTheme.dark()', () {
    final theme = BrandTheme.dark();

    test('uses Material 3 with dark brightness', () {
      expect(theme.useMaterial3, true);
      expect(theme.brightness, Brightness.dark);
    });

    test('colorScheme primary matches BrandColors.primary', () {
      expect(theme.colorScheme.primary, BrandColors.primary);
      expect(theme.colorScheme.onPrimary, BrandColors.onPrimary);
      expect(theme.colorScheme.surface, BrandColors.surface);
      expect(theme.colorScheme.error, BrandColors.error);
    });

    test('scaffoldBackground and canvas use background token', () {
      expect(theme.scaffoldBackgroundColor, BrandColors.background);
      expect(theme.canvasColor, BrandColors.background);
    });

    test('divider color matches BrandColors.divider', () {
      expect(theme.dividerColor, BrandColors.divider);
    });

    test('textTheme uses brand text colors', () {
      expect(theme.textTheme.bodyLarge?.color, BrandColors.textHigh);
      expect(theme.textTheme.bodyMedium?.color, BrandColors.textMedium);
      expect(theme.textTheme.bodySmall?.color, BrandColors.textLow);
    });

    test('cardTheme has rounded border', () {
      final shape = theme.cardTheme.shape as RoundedRectangleBorder?;
      expect(shape, isNotNull);
    });

    test('navigationBarTheme resolves selected and unselected labels', () {
      final labelStyle = theme.navigationBarTheme.labelTextStyle;
      expect(labelStyle, isNotNull);
      // Selected
      final selected = labelStyle!.resolve({WidgetState.selected});
      expect(selected?.color, BrandColors.textHigh);
      expect(selected?.fontWeight, FontWeight.w600);
      // Unselected
      final unselected = labelStyle.resolve({});
      expect(unselected?.color, BrandColors.textMedium);
    });

    test('navigationBarTheme icon states resolve correctly', () {
      final iconStyle = theme.navigationBarTheme.iconTheme;
      expect(iconStyle, isNotNull);
      final selected = iconStyle!.resolve({WidgetState.selected});
      expect(selected?.color, BrandColors.primary);
      final unselected = iconStyle.resolve({});
      expect(unselected?.color, BrandColors.textMedium);
    });

    test('appBarTheme is flat', () {
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.backgroundColor, BrandColors.background);
    });

    test('filledButtonTheme minimum size is 44 tall (accessibility)', () {
      final style = theme.filledButtonTheme.style!;
      final size = style.minimumSize!.resolve({});
      expect(size!.height, 44);
    });
  });

  group('glassCardDecoration', () {
    test('returns a BoxDecoration with expected properties', () {
      final deco = glassCardDecoration();
      expect(deco.gradient, isA<LinearGradient>());
      expect(deco.borderRadius, BorderRadius.circular(BrandRadii.lg));
      expect(deco.border, isNotNull);
      expect(deco.boxShadow, hasLength(1));
    });

    test('respects custom radius', () {
      final deco = glassCardDecoration(radius: 4.0);
      expect(deco.borderRadius, BorderRadius.circular(4.0));
    });
  });
}
