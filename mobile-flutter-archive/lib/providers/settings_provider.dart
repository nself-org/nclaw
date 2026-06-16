/// Settings provider for the 10-tab settings screen (E-26-04).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

const _storageKey = 'nclaw_app_settings';
const _storage = FlutterSecureStorage();

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // First launch or corrupt data; use defaults.
    }
  }

  Future<void> _save() async {
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }

  Future<void> update(AppSettings Function(AppSettings) updater) async {
    state = updater(state);
    await _save();
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);
