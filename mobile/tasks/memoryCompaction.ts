/**
 * Purpose: Register and handle the 'nclaw-memory-compaction' background fetch task.
 *   Triggers NativeNclaw.triggerCompaction() via JSI when the OS wakes the app.
 * Inputs: Called by expo-background-fetch scheduler (OS-controlled interval).
 * Outputs: BackgroundFetch.BackgroundFetchResult.NewData on success, Failed on error.
 * Constraints: Must be registered before the app is backgrounded. JSI bridge must be loaded.
 *   Registration is idempotent — safe to call multiple times.
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-background-fetch
 */
import * as BackgroundFetch from 'expo-background-fetch';
import * as TaskManager from 'expo-task-manager';

// ─── Constants ────────────────────────────────────────────────────────────────

export const MEMORY_COMPACTION_TASK = 'nclaw-memory-compaction';

// ─── NativeNclaw JSI Interface ────────────────────────────────────────────────
// Defined by T-P3-E4-W2-S3-T03 (packages/native-bridge).
// Declared here as ambient to avoid circular import; actual module registered by the bridge.

declare const NativeNclaw:
  | {
      triggerCompaction: () => Promise<void>;
    }
  | undefined;

// ─── Task Definition ──────────────────────────────────────────────────────────

/**
 * Background task handler called by expo-task-manager.
 * MUST be defined at module top level (not inside a component or hook).
 */
TaskManager.defineTask(MEMORY_COMPACTION_TASK, async () => {
  try {
    // Resolve NativeNclaw from global (Nitro modules attach to global scope)
    const nativeModule =
      typeof NativeNclaw !== 'undefined'
        ? NativeNclaw
        : (global as Record<string, unknown>).NativeNclaw as typeof NativeNclaw;

    if (!nativeModule?.triggerCompaction) {
      console.warn(
        '[nclaw-compaction] NativeNclaw.triggerCompaction not available — skipping',
      );
      // Return NewData so the OS schedules again (not a permanent failure)
      return BackgroundFetch.BackgroundFetchResult.NewData;
    }

    await nativeModule.triggerCompaction();
    console.log('[nclaw-compaction] WAL compaction triggered successfully');
    return BackgroundFetch.BackgroundFetchResult.NewData;
  } catch (err) {
    console.error('[nclaw-compaction] Compaction failed:', err);
    return BackgroundFetch.BackgroundFetchResult.Failed;
  }
});

// ─── Registration ─────────────────────────────────────────────────────────────

/**
 * Register the background fetch task with the OS.
 * Call once from +layout.tsx on app startup. Idempotent.
 */
export async function registerMemoryCompactionTask(): Promise<void> {
  try {
    const isRegistered = await TaskManager.isTaskRegisteredAsync(MEMORY_COMPACTION_TASK);
    if (isRegistered) {
      console.log('[nclaw-compaction] Task already registered, skipping');
      return;
    }

    await BackgroundFetch.registerTaskAsync(MEMORY_COMPACTION_TASK, {
      minimumInterval: 15 * 60, // 15 minutes minimum (OS may defer further)
      stopOnTerminate: false,    // Continue after app is force-quit
      startOnBoot: true,         // Re-register after device restart
    });

    console.log('[nclaw-compaction] Background fetch task registered:', MEMORY_COMPACTION_TASK);
  } catch (err) {
    // Non-fatal: background fetch may be unavailable in Expo Go / simulator
    console.warn('[nclaw-compaction] Task registration failed (non-fatal):', err);
  }
}

/**
 * Unregister the task — call only during app uninstall / cleanup flows.
 */
export async function unregisterMemoryCompactionTask(): Promise<void> {
  try {
    const isRegistered = await TaskManager.isTaskRegisteredAsync(MEMORY_COMPACTION_TASK);
    if (isRegistered) {
      await BackgroundFetch.unregisterTaskAsync(MEMORY_COMPACTION_TASK);
      console.log('[nclaw-compaction] Task unregistered');
    }
  } catch (err) {
    console.warn('[nclaw-compaction] Unregister failed:', err);
  }
}
