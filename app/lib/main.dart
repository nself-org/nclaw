import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'screens/pairing_screen.dart';
import 'providers/connection_provider.dart';

void main() {
  runApp(const ProviderScope(child: NClawApp()));
}

class NClawApp extends ConsumerWidget {
  const NClawApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);

    return MaterialApp(
      title: '\u014BClaw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        useMaterial3: true,
      ),
      // Show pairing screen if no servers are paired.
      // Show home screen once at least one server is configured.
      home: connectionState.hasPairedServers
          ? const HomeScreen()
          : const PairingScreen(),
    );
  }
}
