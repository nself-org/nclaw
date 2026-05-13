// T-2728: Toggle for ambient sensor data sharing.
//
// A settings-style toggle that enables/disables ambient context collection
// (motion, location, battery). Default: OFF.

import 'package:flutter/material.dart';

import '../services/ambient_sensor_service.dart';

/// Toggle switch for enabling/disabling ambient sensor context sharing.
///
/// When enabled, starts the [AmbientSensorService] to collect motion,
/// location, and battery data every 30s. When disabled, stops all sensors
/// immediately.
///
/// Usage in a settings screen:
/// ```dart
/// AmbientSettingsToggle(sensorService: myAmbientSensorService)
/// ```
class AmbientSettingsToggle extends StatefulWidget {
  /// The shared sensor service instance. Caller is responsible for
  /// creating and holding the service (typically via a provider).
  final AmbientSensorService sensorService;

  /// Called when the toggle changes. The boolean indicates the new state.
  final ValueChanged<bool>? onChanged;

  const AmbientSettingsToggle({
    super.key,
    required this.sensorService,
    this.onChanged,
  });

  @override
  State<AmbientSettingsToggle> createState() => _AmbientSettingsToggleState();
}

class _AmbientSettingsToggleState extends State<AmbientSettingsToggle> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.sensorService.isActive;
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);

    if (value) {
      await widget.sensorService.start();
    } else {
      widget.sensorService.stop();
    }

    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sensors,
                  color: _enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share ambient context with AI',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Switch.adaptive(
                  value: _enabled,
                  onChanged: _toggle,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Sharing motion, approximate location, and battery level with your AI assistant.'
                  : 'When enabled, your AI can adapt responses based on your current environment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (_enabled && widget.sensorService.latestContext != null) ...[
              const SizedBox(height: 8),
              _ContextPreview(context: widget.sensorService.latestContext!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a compact preview of the current ambient context readings.
class _ContextPreview extends StatelessWidget {
  final AmbientContext context;

  const _ContextPreview({required this.context});

  IconData get _motionIcon => switch (context.motion) {
        MotionState.still => Icons.person_outline,
        MotionState.walking => Icons.directions_walk,
        MotionState.vehicle => Icons.directions_car,
      };

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final chipStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(
          avatar: Icon(_motionIcon, size: 16),
          label: Text(context.motion.toString(), style: chipStyle),
          visualDensity: VisualDensity.compact,
        ),
        if (context.location != null)
          Chip(
            avatar: const Icon(Icons.location_on_outlined, size: 16),
            label: Text(context.location!, style: chipStyle),
            visualDensity: VisualDensity.compact,
          ),
        Chip(
          avatar: Icon(
            context.battery > 20
                ? Icons.battery_std
                : Icons.battery_alert,
            size: 16,
          ),
          label: Text('${context.battery}%', style: chipStyle),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          avatar: const Icon(Icons.access_time, size: 16),
          label: Text(context.time, style: chipStyle),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
