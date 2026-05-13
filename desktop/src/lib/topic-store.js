import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';
export const useTopics = create((set, get) => ({
    topics: [],
    expanded: new Set(),
    active: null,
    collapsed: localStorage.getItem('nclaw.sidebar.collapsed') === 'true',
    async load() {
        const topics = await invoke('list_topics');
        set({ topics });
    },
    toggleExpand(id) {
        set((state) => {
            const next = new Set(state.expanded);
            if (next.has(id)) {
                next.delete(id);
            }
            else {
                next.add(id);
            }
            return { expanded: next };
        });
    },
    setActive(id) {
        set({ active: id });
    },
    setCollapsed(c) {
        localStorage.setItem('nclaw.sidebar.collapsed', String(c));
        set({ collapsed: c });
    },
    async move(fromId, toParentPath) {
        await invoke('move_topic', { fromId, toParentPath });
        await get().load();
    },
    async search(query) {
        return invoke('search', { query });
    },
}));
export function buildTree(topics) {
    const byPath = new Map();
    for (const t of topics) {
        byPath.set(t.path, { topic: t, children: [] });
    }
    const roots = [];
    for (const node of byPath.values()) {
        const parts = node.topic.path.split('.');
        if (parts.length === 1) {
            roots.push(node);
        }
        else {
            const parentPath = parts.slice(0, -1).join('.');
            const parent = byPath.get(parentPath);
            if (parent) {
                parent.children.push(node);
            }
            else {
                roots.push(node);
            }
        }
    }
    return roots;
}
