# Desktop Sidebar

The ɳClaw desktop sidebar shows your life organized by topics, not a list of chat sessions.
There is no "New Chat" button. Topics emerge automatically from your conversations.

## Layout

Fixed width 280px. Collapses to a 56px icon rail via the toggle button on the right edge.
Collapsed state persists in `localStorage` under the key `nclaw.sidebar.collapsed`.

- **Top:** search bar (debounced 200ms)
- **Main:** topic tree with expand/collapse and drag-to-reorder
- **Bottom:** account/status footer

## Collapse / Expand

Click the chevron button on the right edge of the sidebar. In icon-rail mode only the
toggle button and a tree icon are visible. Click either to expand back to full width.

## Empty State

When no topics exist yet, the tree area shows:

> Your topics will appear here as you talk to ɳClaw.

Topics are created automatically by the backend as conversations are classified.
Manual topic creation is available via the context menu on any existing topic.

## Keyboard Navigation

The tree uses standard ARIA `role="tree"` and `role="treeitem"` semantics.
Arrow keys navigate nodes; Enter activates the selected topic.

## Related

- [Topics](topics.md) — topic data model and ltree path format
- [AI Chat](../AI-Chat.md) — how conversations map to topics
