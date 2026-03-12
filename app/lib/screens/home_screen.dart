import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/action_provider.dart';
import '../providers/connection_provider.dart';
import 'action_list_screen.dart';
import 'server_list_screen.dart';

/// Primary screen showing connection status and action queue from nself-claw backend.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final pendingCount = ref.watch(pendingActionCountProvider);
    final theme = Theme.of(context);
    final activeServer = conn.activeServer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u014BClaw'),
        actions: [
          // Action queue badge + navigation.
          IconButton(
            icon: Badge(
              label: Text('$pendingCount'),
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.checklist),
            ),
            tooltip: 'Actions',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ActionListScreen(),
                ),
              );
            },
          ),
          // Server count badge + server list button.
          IconButton(
            icon: Badge(
              label: Text('${conn.servers.length}'),
              isLabelVisible: conn.servers.length > 1,
              child: const Icon(Icons.dns),
            ),
            tooltip: 'Servers',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ServerListScreen(),
                ),
              );
            },
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Expanded(
              child: Center(
                child: Text(
                  conn.status == ConnectionStatus.connected
                      ? pendingCount > 0
                          ? '$pendingCount action${pendingCount == 1 ? '' : 's'} pending approval'
                          : 'Waiting for actions from server...'
                      : 'Not connected',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
