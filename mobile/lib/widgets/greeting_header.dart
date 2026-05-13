/// S21-T02: Personalized greeting header.
///
/// Shows a time-of-day greeting plus the user's display name (from
/// AppSettings.displayName). Falls back to "there" when the name is empty
/// so the greeting always reads naturally.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/brand_theme.dart';

/// Returns the time-of-day greeting for the user's local time.
String timeOfDayGreeting(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return 'Working late';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 22) return 'Good evening';
  return 'Up late';
}

class GreetingHeader extends ConsumerWidget {
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  const GreetingHeader({
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(
      BrandSpacing.xl,
      BrandSpacing.xl,
      BrandSpacing.xl,
      BrandSpacing.md,
    ),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final name = settings.displayName.trim();
    final greeting = timeOfDayGreeting(DateTime.now());
    final fullGreeting =
        name.isEmpty ? '$greeting.' : '$greeting, $name.';

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fullGreeting,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: BrandColors.textHigh,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: BrandSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.textMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
