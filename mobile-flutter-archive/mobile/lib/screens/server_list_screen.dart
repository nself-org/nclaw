import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../providers/connection_provider.dart';
import 'pairing_screen.dart';

/// Screen showing all paired servers with status indicators.
///
/// - Green dot: active + connected
/// - Yellow dot: active + connecting
/// - Red dot: active + error/disconnected
/// - Grey dot: inactive (not the current server)
///
/// Tap to switch, swipe to remove, FAB to add new server.
class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
      ),
      body: conn.servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No servers paired',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add your first server.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conn.servers.length,
              itemBuilder: (context, index) {
                final server = conn.servers[index];
                final isActive = server.id == conn.activeServerId;

                return _ServerTile(
                  server: server,
                  isActive: isActive,
                  connectionStatus: isActive ? conn.status : null,
                  onTap: () {
                    if (!isActive) {
                      ref
                          .read(connectionProvider.notifier)
                          .switchServer(server.id);
                    }
                    Navigator.of(context).pop();
                  },
                  onDismissed: () {
                    ref
                        .read(connectionProvider.notifier)
                        .removeServer(server.id);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PairingScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final ServerConfig server;
  final bool isActive;
  final ConnectionStatus? connectionStatus;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _ServerTile({
    required this.server,
    required this.isActive,
    this.connectionStatus,
    required this.onTap,
    required this.onDismissed,
  });

  Color get _statusColor {
    if (!isActive) return Colors.grey;
    return switch (connectionStatus) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.amber,
      ConnectionStatus.error => Colors.red,
      ConnectionStatus.disconnected => Colors.red,
      null => Colors.grey,
    };
  }

  String get _statusLabel {
    if (!isActive) return 'Inactive';
    return switch (connectionStatus) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.connecting => 'Connecting...',
      ConnectionStatus.error => 'Error',
      ConnectionStatus.disconnected => 'Disconnected',
      null => 'Inactive',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(server.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmRemove(context),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _statusColor,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          server.name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${server.url}  ·  $_statusLabel',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isActive
            ? Icon(Icons.check_circle,
                color: theme.colorScheme.primary, size: 20)
            : null,
        onTap: onTap,
      ),
    );
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove server?'),
        content: Text(
          'Remove "${server.name}" and its stored credentials?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
