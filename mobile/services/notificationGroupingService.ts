/**
 * Purpose: Notification grouping service for ɳClaw mobile.
 *   Manages per-topic Android notification channels so notifications from the same
 *   topic_id are grouped in the Android notification shade. Sets the iOS thread
 *   identifier on the notification handler to group by topic on iOS.
 *   Provides a utility to derive the Android channel ID from a topic_id.
 *
 * Inputs:
 *   - topic_id: canonical auto-topic tag (e.g. 'code', 'planning', 'personal')
 *   - label: human-readable topic name for the Android channel description
 *
 * Outputs:
 *   - Android notification channels created per topic (idempotent)
 *   - channelIdForTopic(topicId) — used by notification payload builders
 *   - threadIdentifierForTopic(topicId) — used for iOS thread grouping
 *   - configureNotificationHandler() — sets the global handler with iOS thread support
 *
 * Constraints:
 *   - Android only: setNotificationChannelAsync is a no-op on iOS — always check Platform.OS.
 *   - Channels are idempotent — calling ensureTopicChannel() twice does not create duplicates.
 *   - iOS grouping uses Notification.threadIdentifier in the notification content.
 *   - Never call this before expo-notifications is initialised (app +layout mount).
 *
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-notification-grouping
 * Cross-ref: T-P3-E4-W2-S3-T14 (FCM + grouping), pushNotificationService.ts
 */

import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

// ─── Constants ────────────────────────────────────────────────────────────────

/** ɳClaw brand color for Android notification LED / icon tint. */
const NCLAW_BRAND_COLOR = '#6C3CE1';

/** Channel ID prefix for per-topic channels. */
const TOPIC_CHANNEL_PREFIX = 'nclaw-topic-';

/** Default channel ID when notification has no topic. */
const DEFAULT_CHANNEL_ID = 'nclaw-default';

// ─── Channel ID helpers ───────────────────────────────────────────────────────

/**
 * Returns the Android notification channel ID for a given topic_id.
 * Falls back to the default channel if topicId is null/undefined/empty.
 *
 * @param topicId  Canonical topic tag or null
 * @returns        Android channel ID string
 */
export function channelIdForTopic(topicId: string | null | undefined): string {
  if (!topicId) return DEFAULT_CHANNEL_ID;
  return `${TOPIC_CHANNEL_PREFIX}${topicId}`;
}

/**
 * Returns the iOS thread identifier for a given topic_id.
 * iOS groups notifications with the same threadIdentifier under one header in
 * Notification Center.
 *
 * @param topicId  Canonical topic tag or null
 * @returns        iOS thread identifier string
 */
export function threadIdentifierForTopic(topicId: string | null | undefined): string {
  if (!topicId) return 'nclaw-default';
  return `nclaw-topic-${topicId}`;
}

// ─── Channel setup ────────────────────────────────────────────────────────────

/**
 * Ensure a per-topic Android notification channel exists.
 * Called lazily when a notification for a new topic arrives, or eagerly on
 * app launch for known canonical topics.
 * Idempotent — setNotificationChannelAsync does nothing if channel already exists.
 *
 * @param topicId  Canonical topic tag
 * @param label    Human-readable label for the channel (shown in OS settings)
 */
export async function ensureTopicChannel(topicId: string, label: string): Promise<void> {
  if (Platform.OS !== 'android') return;

  const channelId = channelIdForTopic(topicId);
  await Notifications.setNotificationChannelAsync(channelId, {
    name: `ɳClaw — ${label}`,
    description: `ɳClaw notifications grouped by topic: ${label}`,
    importance: Notifications.AndroidImportance.DEFAULT,
    vibrationPattern: [0, 100],
    lightColor: NCLAW_BRAND_COLOR,
    enableVibrate: true,
    showBadge: true,
    // Android notification group (all topic channels under one app group)
    groupId: channelId,
  });
}

/**
 * Pre-create channels for all canonical auto-topic tags.
 * Called once at app launch. Ensures grouping works for all known topics
 * without waiting for a notification to arrive.
 */
export async function ensureCanonicalTopicChannels(): Promise<void> {
  if (Platform.OS !== 'android') return;

  const canonicalTopics: Array<{ id: string; label: string }> = [
    { id: 'code',     label: 'Code' },
    { id: 'infra',    label: 'Infrastructure' },
    { id: 'admin',    label: 'Admin' },
    { id: 'personal', label: 'Personal' },
    { id: 'research', label: 'Research' },
    { id: 'question', label: 'Question' },
    { id: 'task',     label: 'Task' },
    { id: 'planning', label: 'Planning' },
    { id: 'general',  label: 'General' },
  ];

  await Promise.all(
    canonicalTopics.map(({ id, label }) => ensureTopicChannel(id, label)),
  );
}

// ─── Global notification handler ──────────────────────────────────────────────

/**
 * Configure the global expo-notifications handler.
 * Sets shouldShowAlert/Sound/Badge and configures iOS thread identifier grouping.
 * Call once at app launch (before the first notification can arrive).
 */
export function configureNotificationHandler(): void {
  Notifications.setNotificationHandler({
    handleNotification: async (notification) => {
      // Extract topic_id from notification payload for iOS thread grouping
      const data = notification.request.content.data as Record<string, unknown> | undefined;
      const topicId = typeof data?.topic_id === 'string' ? data.topic_id : null;

      return {
        shouldShowAlert: true,
        shouldPlaySound: true,
        shouldSetBadge: false,
        // iOS: group notifications by topic
        ...(Platform.OS === 'ios' && topicId
          ? { threadIdentifier: threadIdentifierForTopic(topicId) }
          : {}),
      };
    },
  });
}
