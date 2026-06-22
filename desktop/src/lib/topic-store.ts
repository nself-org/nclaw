import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

/** A topic node in the sidebar tree, backed by an ltree path in Postgres. */
export interface Topic {
  id: string;
  path: string;
  name: string;
  archived: boolean;
}

/** Full-text search result: matching topics and ids of topics that contain matching messages. */
export interface SearchResult {
  topics: Topic[];
  matched_message_topics: string[];
}

interface TopicStoreState {
  topics: Topic[];
  expanded: Set<string>;
  active: string | null;
  collapsed: boolean;
  load(): Promise<void>;
  toggleExpand(id: string): void;
  setActive(id: string): void;
  setCollapsed(c: boolean): void;
  move(fromId: string, toParentPath: string): Promise<void>;
  search(query: string): Promise<SearchResult>;
}

/** Zustand store for the sidebar topic tree. Load once on mount; mutations call Tauri invoke. */
export const useTopics = create<TopicStoreState>((set, get) => ({
  topics: [],
  expanded: new Set(),
  active: null,
  collapsed: localStorage.getItem('nclaw.sidebar.collapsed') === 'true',

  async load() {
    const topics = await invoke<Topic[]>('list_topics');
    set({ topics });
  },

  toggleExpand(id: string) {
    set((state) => {
      const next = new Set(state.expanded);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return { expanded: next };
    });
  },

  setActive(id: string) {
    set({ active: id });
  },

  setCollapsed(c: boolean) {
    localStorage.setItem('nclaw.sidebar.collapsed', String(c));
    set({ collapsed: c });
  },

  async move(fromId: string, toParentPath: string) {
    await invoke('move_topic', { fromId, toParentPath });
    await get().load();
  },

  async search(query: string): Promise<SearchResult> {
    return invoke<SearchResult>('search', { query });
  },
}));

/** Build a nested tree from flat topic list keyed by ltree path. */
export interface TreeNode {
  topic: Topic;
  children: TreeNode[];
}

/** Build a nested `TreeNode[]` from a flat ltree-path topic list. Orphaned nodes become roots. */
export function buildTree(topics: Topic[]): TreeNode[] {
  const byPath = new Map<string, TreeNode>();
  for (const t of topics) {
    byPath.set(t.path, { topic: t, children: [] });
  }
  const roots: TreeNode[] = [];
  for (const node of byPath.values()) {
    const parts = node.topic.path.split('.');
    if (parts.length === 1) {
      roots.push(node);
    } else {
      const parentPath = parts.slice(0, -1).join('.');
      const parent = byPath.get(parentPath);
      if (parent) {
        parent.children.push(node);
      } else {
        roots.push(node);
      }
    }
  }
  return roots;
}
