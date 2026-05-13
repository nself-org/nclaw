import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/action_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/greeting_header.dart';
import '../widgets/knowledge_search_sheet.dart';
import '../widgets/topic_drawer.dart';
import '../widgets/voice_capture_fab.dart';
import 'action_list_screen.dart';
import 'chat_screen.dart';
import 'memory_explorer_screen.dart';
import 'server_list_screen.dart';
import 'settings_screen.dart';

/// Provider holding the currently selected bottom-nav tab index.
///
/// Exposed so that the deep-link handler in main.dart can switch tabs
/// (e.g. `nclaw://chat` → set to 0).
final homeTabProvider = StateProvider<int>((ref) => 0);

/// Primary screen with bottom navigation: Chat / Actions / Servers.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final pendingCount = ref.watch(pendingActionCountProvider);
    final selectedTab = ref.watch(homeTabProvider);
    final activeServer = conn.activeServer;

    final tabs = [
      const ChatScreen(),
      const MemoryExplorerScreen(),
      _ActionsTab(conn: conn, pendingCount: pendingCount),
      const ServerListScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u0273Claw'),
        actions: [
          // Settings.
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen()),
            ),
          ),
          // Disconnect from active server.
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
            onPressed: () async {
              if (activeServer != null) {
                await ref
                    .read(connectionProvider.notifier)
                    .removeServer(activeServer.id);
              }
            },
          ),
        ],
      ),
      // E-26-01: Topic drawer (swipe from left).
      drawer: const TopicDrawer(),
      body: tabs[selectedTab],
      // E-26-08a: Voice capture FAB on chat tab, knowledge FAB otherwise.
      floatingActionButton: conn.status == ConnectionStatus.connected
          ? selectedTab == 0
              ? VoiceCaptureFab(
                  onTranscribed: (text) {
                    // Insert transcribed text into chat composer.
                    // The ChatScreen handles this via a provider or callback.
                  },
                )
              : FloatingActionButton.small(
                  heroTag: 'quick_help_fab',
                  tooltip: '\u0273Self knowledge base',
                  onPressed: () => showKnowledgeSearchSheet(context),
                  child: const Icon(Icons.menu_book_rounded),
                )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          ref.read(homeTabProvider.notifier).state = index;
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Memory',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('$pendingCount'),
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.bolt_outlined),
            ),
            selectedIcon: Badge(
              label: Text('$pendingCount'),
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.bolt),
            ),
            label: 'Actions',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${conn.servers.length}'),
              isLabelVisible: conn.servers.length > 1,
              child: const Icon(Icons.dns_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${conn.servers.length}'),
              isLabelVisible: conn.servers.length > 1,
              child: const Icon(Icons.dns),
            ),
            label: 'Servers',
          ),
        ],
      ),
    );
  }
}

/// Actions tab: connection status card + action queue shortcut.
///
/// This preserves the original home screen body content under the new
/// bottom-nav shell.
class _ActionsTab extends ConsumerWidget {
  final ConnectionState conn;
  final int pendingCount;

  const _ActionsTab({
    required this.conn,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeServer = conn.activeServer;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // S21-T02: Personalized time-of-day greeting.
          const GreetingHeader(
            padding: EdgeInsets.only(bottom: 16),
            subtitle: null,
          ),
          _ConnectionStatusCard(
            status: conn.status,
            serverName: activeServer?.name ?? 'No server',
            serverUrl: activeServer?.url ?? '',
            onReconnect: () {
              ref.read(connectionProvider.notifier).reconnect();
            },
          ),
          const SizedBox(height: 24),
          // Action queue header with badge.
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ActionListScreen(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Text(
                  'Action Queue',
                  style: theme.textTheme.titleMedium,
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 8),
                  Badge(
                    label: Text('$pendingCount'),
                    child: const SizedBox.shrink(),
                  ),
                ],
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // S21-T05: Consistent empty states across all seven states.
          Expanded(
            child: _buildActionsEmptyState(context, ref, conn, pendingCount),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsEmptyState(
    BuildContext context,
    WidgetRef ref,
    ConnectionState conn,
    int pendingCount,
  ) {
    if (conn.status == ConnectionStatus.disconnected ||
        conn.status == ConnectionStatus.error) {
      return EmptyState.offline(
        title: 'Not connected',
        message: 'Reconnect to your nSelf server to receive actions.',
        onRetry: () => ref.read(connectionProvider.notifier).reconnect(),
      );
    }
    if (pendingCount > 0) {
      return EmptyState(
        icon: Icons.bolt,
        title:
            '$pendingCount action${pendingCount == 1 ? '' : 's'} pending approval',
        message: 'Tap Action Queue to review them.',
        primaryAction: EmptyStateAction(
          label: 'Review',
          icon: Icons.chevron_right,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ActionListScreen(),
            ),
          ),
        ),
      );
    }
    return EmptyState.firstTime(
      icon: Icons.inbox_outlined,
      title: 'No actions waiting',
      message: "Approved actions from ɳClaw will appear here.",
    );
  }
}

/// Color-coded connection status card.
///
/// Green: connected. Yellow/amber: connecting. Red: error or disconnected.
class _ConnectionStatusCard extends StatelessWidget {
  final ConnectionStatus status;
  final String serverName;
  final String serverUrl;
  final VoidCallback onReconnect;

  const _ConnectionStatusCard({
    required this.status,
    required this.serverName,
    required this.serverUrl,
    required this.onReconnect,
  });

  Color get _statusColor => switch (status) {
        ConnectionStatus.connected => Colors.green,
        ConnectionStatus.connecting => Colors.amber,
        ConnectionStatus.error => Colors.red,
        ConnectionStatus.disconnected => Colors.red,
      };

  String get _statusText => switch (status) {
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.connecting => 'Connecting...',
        ConnectionStatus.error => 'Connection error',
        ConnectionStatus.disconnected => 'Disconnected',
      };

  IconData get _statusIcon => switch (status) {
        ConnectionStatus.connected => Icons.check_circle,
        ConnectionStatus.connecting => Icons.sync,
        ConnectionStatus.error => Icons.error_outline,
        ConnectionStatus.disconnected => Icons.cloud_off,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showReconnect =
        status == ConnectionStatus.error ||
        status == ConnectionStatus.disconnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status indicator dot.
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            // Server info.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_statusIcon, size: 16, color: _statusColor),
                      const SizedBox(width: 6),
                      Text(
                        _statusText,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: _statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    serverName,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (serverUrl.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      serverUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Reconnect button when disconnected or error.
            if (showReconnect)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reconnect',
                onPressed: onReconnect,
              ),
          ],
        ),
      ),
    );
  }
}
