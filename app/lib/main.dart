import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'screens/digest_viewer_screen.dart';
import 'screens/home_screen.dart';
import 'screens/pairing_screen.dart';
import 'providers/connection_provider.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';

// Top-level background handler — must be registered before runApp.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) =>
    firebaseMessagingBackgroundHandler(message);

/// Stores the latest deep-link route received while the app is running.
///
/// Route values mirror the `nclaw://` host component:
/// - `"usage"` — navigate to the usage dashboard
/// - `"setup"` — navigate to the onboarding/setup wizard
/// - `"digest"` — navigate to the daily digest
/// - `"topics"` — navigate to topic detail (see [deepLinkPayloadProvider] for id)
/// - `"memories"` — navigate to memory detail (see [deepLinkPayloadProvider] for id)
/// Consumers watch this provider and react accordingly.
final deepLinkRouteProvider = StateProvider<String?>((ref) => null);

/// S22-T10: Payload for parameterised deep links.
///
/// Carries an optional id so consumers can navigate to a specific topic or
/// memory. Cleared by the consumer screen after routing.
class DeepLinkPayload {
  final String route;
  final String? id;
  const DeepLinkPayload({required this.route, this.id});
}

final deepLinkPayloadProvider =
    StateProvider<DeepLinkPayload?>((ref) => null);

/// Returns `true` when the backend reports that first-run setup is not
/// complete (i.e. `/claw/setup/status` returns a `status` value other than
/// `"complete"`).
///
/// Falls back to `false` on any network or parse error so the onboarding
/// wizard is not shown unnecessarily when the server is unreachable.
final onboardingNeededProvider = FutureProvider<bool>((ref) async {
  final serverUrl =
      ref.watch(connectionProvider).activeServer?.url;
  if (serverUrl == null || serverUrl.isEmpty) return false;
  try {
    final uri = Uri.parse('$serverUrl/claw/setup/status');
    final response =
        await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final status = data['status'] as String?;
        return status != null && status != 'complete';
      }
    }
  } catch (_) {
    // Network error — assume setup is complete to avoid blocking the user.
  }
  return false;
});

/// Global navigator key — used by NotificationService for tap-to-navigate.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // T-1197: Initialize Firebase + register background handler.
  // If google-services.json / GoogleService-Info.plist are absent (e.g. CI
  // builds or users who haven't set up Firebase), this is a no-op and push
  // notifications are simply unavailable.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.initialize(navigatorKey: navigatorKey);
  } catch (e) {
    // Firebase not configured — push notifications unavailable.
    debugPrint('[main] Firebase init skipped: $e');
  }

  runApp(const ProviderScope(child: NClawApp()));
}

class NClawApp extends ConsumerStatefulWidget {
  const NClawApp({super.key});

  @override
  ConsumerState<NClawApp> createState() => _NClawAppState();
}

class _NClawAppState extends ConsumerState<NClawApp> {
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle cold-start link (app launched via nclaw:// while not running).
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleLink(initial);

    // Handle links received while the app is already running.
    _appLinks.uriLinkStream.listen(_handleLink);
  }

  void _handleLink(Uri uri) {
    // S22-T10: accept nclaw://, claw://, and https://claw.nself.org/* App Links.
    // App Links arrive with scheme https; map /topics/:id and /memories/:id
    // onto the same handlers as the custom schemes.
    final isCustomScheme = uri.scheme == 'nclaw' || uri.scheme == 'claw';
    final isAppLink = uri.scheme == 'https' &&
        (uri.host == 'claw.nself.org' || uri.host == 'nself.org');
    if (!isCustomScheme && !isAppLink) return;

    // Normalize: for custom-scheme URIs the target is the host
    // (nclaw://topics/<id>); for App Links the target is the first path
    // segment (https://claw.nself.org/topics/<id>).
    final target = isCustomScheme
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    final trailing = isCustomScheme
        ? uri.pathSegments
        : uri.pathSegments.skip(1).toList();

    if (target == 'pair') {
      final server = uri.queryParameters['server'];
      final code = uri.queryParameters['code'];
      if (server != null && code != null && code.isNotEmpty) {
        ref.read(pendingPairProvider.notifier).state = PairParams(
          serverUrl: server,
          code: code.toUpperCase(),
        );
      }
    } else if (target == 'chat') {
      // Switch to the Chat tab (index 0) in HomeScreen.
      ref.read(homeTabProvider.notifier).state = 0;
      if (trailing.isNotEmpty) {
        // Optional: nclaw://chat/<conversation_id>
        ref.read(deepLinkPayloadProvider.notifier).state =
            DeepLinkPayload(route: 'chat', id: trailing.first);
      }
    } else if (target == 'topics') {
      // nclaw://topics/<topic_id> or https://claw.nself.org/topics/<topic_id>
      final topicId = trailing.isNotEmpty ? trailing.first : null;
      ref.read(deepLinkPayloadProvider.notifier).state =
          DeepLinkPayload(route: 'topics', id: topicId);
      ref.read(deepLinkRouteProvider.notifier).state = 'topics';
    } else if (target == 'memories') {
      // nclaw://memories/<memory_id> or https://claw.nself.org/memories/<id>
      final memoryId = trailing.isNotEmpty ? trailing.first : null;
      ref.read(deepLinkPayloadProvider.notifier).state =
          DeepLinkPayload(route: 'memories', id: memoryId);
      ref.read(deepLinkRouteProvider.notifier).state = 'memories';
    } else if (target == 'usage' ||
        target == 'setup' ||
        target == 'digest') {
      // Signal consumers (e.g. HomeScreen) to navigate to the target screen.
      ref.read(deepLinkRouteProvider.notifier).state = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '\u0273Claw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        useMaterial3: true,
      ),
      routes: {
        DigestViewerScreen.routeName: (_) => const DigestViewerScreen(),
      },
      // Show pairing screen if no servers are paired.
      // Show home screen once at least one server is configured.
      home: connectionState.hasPairedServers
          ? const HomeScreen()
          : const PairingScreen(),
    );
  }
}
