/**
 * useAutoTopics — subscribe to auto-classified topics and keep the sidebar current.
 *
 * Purpose: Opens a GraphQL subscription on topic_auto_classify, which fires whenever
 *          the nclaw inference engine classifies a new or updated topic from the active
 *          conversation. The hook merges incoming Topic objects into a sorted list that
 *          the Topics sidebar (T02 screen) renders.
 *
 * Inputs:  userId — the authenticated user's ID (used to scope the subscription).
 * Outputs: { topics, loading, error } — live-updating list of Topic objects.
 *
 * Constraints:
 *   - Subscription is opened once on mount and torn down on unmount.
 *   - Incoming topics are merged by id — a repeated id updates rather than appends.
 *   - No memory / chat logic lives in this hook; it is purely topic classification.
 *   - If userId is undefined (unauthenticated), subscription is skipped (skip: true).
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T02 (Topics sidebar screen), T-P3-E4-W1-S1-T01 (feature spec §2).
 */

import { useEffect, useMemo, useState } from 'react';
import { useSubscription, gql } from '@apollo/client';
import type { Topic } from '@nself/native-bridge';

// ---------------------------------------------------------------------------
// GraphQL subscription
// ---------------------------------------------------------------------------

const TOPIC_AUTO_CLASSIFY_SUBSCRIPTION = gql`
  subscription TopicAutoClassify($userId: String!) {
    topic_auto_classify(where: { user_id: { _eq: $userId } }) {
      id
      userId: user_id
      title
      description
      createdAt: created_at
      updatedAt: updated_at
      entityCount: entity_count
      conversationCount: conversation_count
    }
  }
`;

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

interface TopicAutoClassifyRow {
  id: string;
  userId: string;
  title: string;
  description: string | null;
  createdAt: string;
  updatedAt: string;
  entityCount: number;
  conversationCount: number;
}

interface TopicAutoClassifyData {
  topic_auto_classify: TopicAutoClassifyRow[];
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export interface UseAutoTopicsResult {
  /** Live-updating, deduplicated list of classified topics (newest-first by updatedAt). */
  topics: Topic[];
  /** True while the subscription is establishing. */
  loading: boolean;
  /** Non-null when the subscription encounters a network or GraphQL error. */
  error: Error | null;
}

/**
 * Hook: subscribe to topic_auto_classify and maintain a deduped topic list.
 *
 * Usage in Topics sidebar (T02):
 *   const { topics, loading } = useAutoTopics(userId);
 */
export function useAutoTopics(userId: string | undefined): UseAutoTopicsResult {
  const [topicsMap, setTopicsMap] = useState<Map<string, Topic>>(new Map());

  const { data, loading, error } = useSubscription<TopicAutoClassifyData>(
    TOPIC_AUTO_CLASSIFY_SUBSCRIPTION,
    {
      variables: { userId },
      skip: !userId,
    },
  );

  // Merge incoming rows into the running deduped map.
  useEffect(() => {
    if (!data?.topic_auto_classify) return;

    setTopicsMap((prev) => {
      const next = new Map(prev);
      for (const row of data.topic_auto_classify) {
        next.set(row.id, {
          id: row.id,
          userId: row.userId,
          title: row.title,
          description: row.description,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          entityCount: row.entityCount,
          conversationCount: row.conversationCount,
        });
      }
      return next;
    });
  }, [data]);

  // Sort newest-first by updatedAt for stable rendering.
  const topics = useMemo(
    () =>
      Array.from(topicsMap.values()).sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      ),
    [topicsMap],
  );

  return {
    topics,
    loading,
    error: error ?? null,
  };
}
