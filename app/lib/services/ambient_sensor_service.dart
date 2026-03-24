// T-2728: Ambient sensor data collection — motion, location, battery.
//
// Collects environmental context every 30s when enabled. Data is packaged
// as a JSON map suitable for injection into chat messages as ambient context.
//
// Requires packages: sensors_plus, geolocator, battery_plus.

import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Motion classification derived from accelerometer magnitude variance.
enum MotionState {
  still,
  walking,
  vehicle;

  @override
  String toString() => name;
}

/// Snapshot of ambient sensor readings.
class AmbientContext {
  final MotionState motion;
  final String? location; // "City, Region" or null if unavailable
  final int battery; // 0–100
  final String time; // "HH:MM local"

  const AmbientContext({
    required this.motion,
    this.location,
    required this.battery,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'motion': motion.toString(),
        if (location != null) 'location': location,
        'battery': battery,
        'time': time,
      };
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Collects ambient sensor data at a regular interval.
///
/// Usage:
/// ```dart
/// final sensor = AmbientSensorService();
/// await sensor.start();
/// final ctx = sensor.latestContext;  // nullable
/// sensor.stop();
/// ```
class AmbientSensorService {
  static const _collectInterval = Duration(seconds: 30);

  final Battery _battery = Battery();
  Timer? _timer;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  /// Most recent collected context. Null until first collection completes.
  AmbientContext? latestContext;

  /// Whether the service is actively collecting.
  bool get isActive => _timer != null;

  // Accelerometer state for motion classification.
  final List<double> _recentMagnitudes = [];
  static const _magnitudeWindowSize = 30; // ~3s at 10Hz sampling

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Start collecting ambient data every 30 seconds.
  ///
  /// Requests location permission if not already granted. If denied,
  /// location will be omitted from the context.
  Future<void> start() async {
    if (isActive) return;

    // Start accelerometer stream for motion detection.
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelerometerEvent);

    // Collect immediately, then every 30s.
    await _collect();
    _timer = Timer.periodic(_collectInterval, (_) => _collect());
  }

  /// Stop all sensor collection and release resources.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _accelSub?.cancel();
    _accelSub = null;
    _recentMagnitudes.clear();
    latestContext = null;
  }

  // -------------------------------------------------------------------------
  // Collection
  // -------------------------------------------------------------------------

  Future<void> _collect() async {
    final motion = _classifyMotion();
    final batteryLevel = await _getBatteryLevel();
    final location = await _getCoarseLocation();

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} local';

    latestContext = AmbientContext(
      motion: motion,
      location: location,
      battery: batteryLevel,
      time: timeStr,
    );
  }

  // -------------------------------------------------------------------------
  // Motion classification
  // -------------------------------------------------------------------------

  void _onAccelerometerEvent(AccelerometerEvent event) {
    // Compute magnitude (gravity included, ~9.8 m/s^2 at rest).
    final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    _recentMagnitudes.add(mag);
    if (_recentMagnitudes.length > _magnitudeWindowSize) {
      _recentMagnitudes.removeAt(0);
    }
  }

  /// Classify motion from accelerometer magnitude variance.
  ///
  /// - Still: variance < 0.5 (device at rest or in pocket, steady)
  /// - Walking: 0.5 <= variance < 8.0 (rhythmic step-like oscillation)
  /// - Vehicle: variance >= 8.0 (high vibration / rapid changes)
  MotionState _classifyMotion() {
    if (_recentMagnitudes.length < 5) return MotionState.still;

    final mean =
        _recentMagnitudes.reduce((a, b) => a + b) / _recentMagnitudes.length;
    final variance = _recentMagnitudes
            .map((m) => (m - mean) * (m - mean))
            .reduce((a, b) => a + b) /
        _recentMagnitudes.length;

    if (variance < 0.5) return MotionState.still;
    if (variance < 8.0) return MotionState.walking;
    return MotionState.vehicle;
  }

  // -------------------------------------------------------------------------
  // Battery
  // -------------------------------------------------------------------------

  Future<int> _getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return -1;
    }
  }

  // -------------------------------------------------------------------------
  // Location (coarse, city-level)
  // -------------------------------------------------------------------------

  /// Get coarse location. Returns "lat,lon" or null.
  ///
  /// Uses low accuracy (~1km) to minimize battery drain. Does not reverse
  /// geocode to city name (that would require an additional package or API).
  /// The AI model can interpret coordinates if needed.
  Future<String?> _getCoarseLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Return as a compact lat/lon string (city-level precision).
      final lat = position.latitude.toStringAsFixed(2);
      final lon = position.longitude.toStringAsFixed(2);
      return '$lat,$lon';
    } catch (_) {
      return null;
    }
  }
}
