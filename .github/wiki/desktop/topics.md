# Topics

Topics are the organizational unit in ɳClaw. Every conversation belongs to a topic.
Topics are detected automatically; you can also rename, nest, archive, or delete them.

## Data Model

```ts
interface Topic {
  id: string;       // UUID
  path: string;     // ltree path, e.g. "work.projects.nself"
  name: string;     // human-readable label, e.g. "nSelf"
  archived: boolean;
}
```

Paths use PostgreSQL `ltree` dot notation. A topic at `work.projects.nself` is a
child of `work.projects`, which is a child of `work`.

## Tree Structure

The sidebar builds a nested tree from the flat path list. Siblings at the same
parent share a visual indent guide (vertical line + connecting dot).

## Drag-to-Reorder

Grab the six-dot handle that appears on hover and drag a topic to a new position
within the same parent group. Cross-parent moves re-parent the topic.
The new position is persisted by calling `move_topic(from_id, to_parent_path)` on the backend.

## Context Menu Actions

Right-click (or click the three-dot icon) on any topic:

| Action | Effect |
|--------|--------|
| New Subtopic | Creates a child topic |
| Rename | Edits the display name |
| Archive | Hides from tree, retrievable via filter |
| Delete | Permanently removes topic and reassigns messages |
| Export | Downloads topic + messages as JSON |

## Search

The search bar filters the tree in real time (200ms debounce). Matching topics are
highlighted; topics containing matching messages are also surfaced with their parent
chain expanded. Clear the query to restore the full tree.

## Backend Commands

Wired via Tauri `invoke`:

- `list_topics` — returns all non-archived topics
- `move_topic(from_id, to_parent_path)` — persists drag-reorder
- `search(query)` — returns matching topics and message-topic IDs

Full DB implementation (ltree + MeiliSearch) lands in S17.
