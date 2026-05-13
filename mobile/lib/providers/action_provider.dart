import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claw_action.dart';
import '../services/action_executor_service.dart';
import '../services/action_queue_service.dart';
import '../services/claw_client.dart';

/// Which tab is active in the action list screen.
enum ActionTab { pending, active, history }

/// State for the action queue UI.
class ActionQueueState {
  final List<ClawAction> pending;
  final List<ClawAction> active;
  final List<ClawAction> history;
  final bool loading;

  const ActionQueueState({
    this.pending = const [],
    this.active = const [],
    this.history = const [],
    this.loading = true,
  });

  /// Count of actions awaiting user approval.
  int get pendingCount => pending.length;

  ActionQueueState copyWith({
    List<ClawAction>? pending,
    List<ClawAction>? active,
    List<ClawAction>? history,
    bool? loading,
  }) {
    return ActionQueueState(
      pending: pending ?? this.pending,
      active: active ?? this.active,
      history: history ?? this.history,
      loading: loading ?? this.loading,
    );
  }
}

/// Manages the action queue state and bridges UI to [ActionQueueService].
class ActionNotifier extends StateNotifier<ActionQueueState> {
  final ActionQueueService _service;
  ClawClient? _client;
  StreamSubscription<void>? _changeSub;
  Timer? _expireTimer;

  ActionNotifier(this._service) : super(const ActionQueueState()) {
    _init();
  }

  /// Wire in the WebSocket client after construction.
  ///
  /// Called by [ConnectionNotifier] once it has a live [ClawClient].
  /// Using a setter avoids a circular import between action_provider and
  /// connection_provider.
  void setClient(ClawClient client) {
    _client = client;
  }

  Future<void> _init() async {
    await _service.init();

    // Expire stale actions on startup.
    await _service.expireOldActions();

    // Listen for database changes and refresh.
    _changeSub = _service.onChange.listen((_) => _refresh());

    // Periodically expire old actions (every 5 minutes).
    _expireTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _service.expireOldActions();
    });

    await _refresh();
  }

  /// Reload all action lists from the database.
  Future<void> _refresh() async {
    final pending = await _service.getByStatus([ActionStatus.pending]);
    // Filter out actions that are actually expired but not yet marked.
    final validPending = pending.where((a) => !a.isExpired).toList();

    final active = await _service.getByStatus([
      ActionStatus.approved,
      ActionStatus.executing,
    ]);

    final history = await _service.getByStatus([
      ActionStatus.done,
      ActionStatus.failed,
      ActionStatus.expired,
    ]);

    if (mounted) {
      state = ActionQueueState(
        pending: validPending,
        active: active,
        history: history,
        loading: false,
      );
    }
  }

  /// Refresh from UI (pull-to-refresh).
  Future<void> refresh() async {
    await _service.expireOldActions();
    await _refresh();
  }

  /// Approve a pending action, execute it, and send the result over WebSocket.
  Future<void> approve(String actionId) async {
    // 1. Mark approved so the UI reflects the transition immediately.
    await _service.updateStatus(actionId, ActionStatus.approved);

    // 2. Load the full action from the queue.
    final action = await _service.getById(actionId);
    if (action == null) return;

    // 3. Mark as executing.
    await _service.updateStatus(actionId, ActionStatus.executing);

    // 4. Run the action on-device.
    final result = await ActionExecutorService().execute(action);

    // 5. Determine terminal status from result.
    final isError = result.containsKey('error');
    final isPending = result['pending'] == true; // OAuth awaiting deep link
    final terminalStatus =
        isError ? ActionStatus.failed : ActionStatus.done;

    // For OAuth actions that opened the browser, stay in 'executing' until
    // the deep link callback arrives via OAuthService.completeOAuth().
    if (!isPending) {
      await _service.updateStatus(actionId, terminalStatus, result: result);
    }

    // 6. Send result back to the server over WebSocket (if connected).
    _client?.send({
      'type': 'action_result',
      'actionId': actionId,
      'status': isPending ? 'executing' : terminalStatus.toJson(),
      'result': result,
    });
  }

  /// Deny a pending action. Marks it as failed with a denial reason.
  Future<void> deny(String actionId) async {
    await _service.updateStatus(
      actionId,
      ActionStatus.failed,
      result: {'error': 'Denied by user'},
    );
  }

  /// Retry a failed action by resetting it to pending.
  Future<void> retry(String actionId) async {
    await _service.updateStatus(actionId, ActionStatus.pending);
  }

  /// Get a single action by id.
  Future<ClawAction?> getAction(String actionId) async {
    return _service.getById(actionId);
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _expireTimer?.cancel();
    super.dispose();
  }
}

/// Singleton action queue service shared across the app.
final actionQueueServiceProvider = Provider<ActionQueueService>((ref) {
  final service = ActionQueueService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// The action queue state provider.
///
/// The [ClawClient] is wired in post-construction via [ActionNotifier.setClient],
/// called by [ConnectionNotifier] to avoid a circular import.
final actionProvider =
    StateNotifierProvider<ActionNotifier, ActionQueueState>((ref) {
  final service = ref.watch(actionQueueServiceProvider);
  return ActionNotifier(service);
});

/// Convenience provider for pending action count (used for badges).
final pendingActionCountProvider = Provider<int>((ref) {
  return ref.watch(actionProvider).pendingCount;
});
