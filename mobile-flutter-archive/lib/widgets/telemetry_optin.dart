import 'package:flutter/material.dart';

/// TelemetryOptinWidget — S20.T09 telemetry opt-in dialog + UI wiring.
///
/// Prompts user to opt-in to telemetry on first launch.
/// Persists preference via vault (see vault_service.dart).
class TelemetryOptinWidget extends StatefulWidget {
  final VoidCallback onOptinChanged;

  const TelemetryOptinWidget({required this.onOptinChanged});

  @override
  State<TelemetryOptinWidget> createState() => _TelemetryOptinWidgetState();
}

class _TelemetryOptinWidgetState extends State<TelemetryOptinWidget> {
  bool _optin = false;

  void _handleOptinChange(bool? value) {
    setState(() => _optin = value ?? false);
    widget.onOptinChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Help improve ɳClaw',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Send anonymous usage data to help us improve the app?',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Yes, opt-in'),
              value: _optin,
              onChanged: _handleOptinChange,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_optin),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
