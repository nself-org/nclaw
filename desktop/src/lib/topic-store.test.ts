/**
 * Unit tests for topic-store — zustand store covering load, toggleExpand,
 * setActive, setCollapsed, move, search, and the buildTree utility.
 *
 * All Tauri invoke calls are mocked deterministically.  No real IPC or network.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

// --- Mock Tauri core -------------------------------------------------------
const { mockInvoke } = vi.hoisted(() => ({ mockInvoke: vi.fn() }))
vi.mock('@tauri-apps/api/core', () => ({ invoke: mockInvoke }))

// --- Mock localStorage (jsdom provides it but we want deterministic reset) --
const localStorageMock = (() => {
  let store: Record<string, string> = {}
  return {
    getItem: (key: string) => store[key] ?? null,
    setItem: (key: string, value: string) => { store[key] = value },
    removeItem: (key: string) => { delete store[key] },
    clear: () => { store = {} },
  }
})()

Object.defineProperty(globalThis, 'localStorage', {
  value: localStorageMock,
  writable: true,
})

import { useTopics, buildTree } from './topic-store'
import type { Topic } from './topic-store'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TOPIC_A: Topic = { id: 'a', path: 'a', name: 'Alpha', archived: false }
const TOPIC_B: Topic = { id: 'b', path: 'a.b', name: 'Bravo', archived: false }
const TOPIC_C: Topic = { id: 'c', path: 'c', name: 'Charlie', archived: false }

function resetStore() {
  // Partial update only — do NOT use replace=true which would strip actions in zustand v5
  useTopics.setState({
    topics: [],
    expanded: new Set(),
    active: null,
    collapsed: false,
  })
  localStorageMock.clear()
  mockInvoke.mockReset()
}

// ---------------------------------------------------------------------------

describe('useTopics — load', () => {
  beforeEach(resetStore)

  it('populates topics from invoke("list_topics")', async () => {
    mockInvoke.mockResolvedValueOnce([TOPIC_A, TOPIC_C])
    await useTopics.getState().load()
    expect(useTopics.getState().topics).toEqual([TOPIC_A, TOPIC_C])
  })

  it('calls list_topics with no extra args', async () => {
    mockInvoke.mockResolvedValueOnce([])
    await useTopics.getState().load()
    expect(mockInvoke).toHaveBeenCalledWith('list_topics')
  })

  it('starts with empty topics before load', () => {
    expect(useTopics.getState().topics).toHaveLength(0)
  })

  it('replaces existing topics on second load', async () => {
    mockInvoke.mockResolvedValueOnce([TOPIC_A])
    await useTopics.getState().load()
    mockInvoke.mockResolvedValueOnce([TOPIC_C])
    await useTopics.getState().load()
    expect(useTopics.getState().topics).toEqual([TOPIC_C])
  })
})

// ---------------------------------------------------------------------------

describe('useTopics — toggleExpand', () => {
  beforeEach(resetStore)

  it('adds id to expanded set when not present', () => {
    useTopics.getState().toggleExpand('a')
    expect(useTopics.getState().expanded.has('a')).toBe(true)
  })

  it('removes id from expanded set when already present', () => {
    useTopics.getState().toggleExpand('a')
    useTopics.getState().toggleExpand('a')
    expect(useTopics.getState().expanded.has('a')).toBe(false)
  })

  it('tracks multiple expanded ids independently', () => {
    useTopics.getState().toggleExpand('a')
    useTopics.getState().toggleExpand('b')
    const { expanded } = useTopics.getState()
    expect(expanded.has('a')).toBe(true)
    expect(expanded.has('b')).toBe(true)
  })

  it('collapsing one id does not affect another', () => {
    useTopics.getState().toggleExpand('a')
    useTopics.getState().toggleExpand('b')
    useTopics.getState().toggleExpand('a')
    const { expanded } = useTopics.getState()
    expect(expanded.has('a')).toBe(false)
    expect(expanded.has('b')).toBe(true)
  })
})

// ---------------------------------------------------------------------------

describe('useTopics — setActive', () => {
  beforeEach(resetStore)

  it('sets the active id', () => {
    useTopics.getState().setActive('a')
    expect(useTopics.getState().active).toBe('a')
  })

  it('replaces a previous active id', () => {
    useTopics.getState().setActive('a')
    useTopics.getState().setActive('b')
    expect(useTopics.getState().active).toBe('b')
  })

  it('starts as null before setActive is called', () => {
    expect(useTopics.getState().active).toBeNull()
  })
})

// ---------------------------------------------------------------------------

describe('useTopics — setCollapsed', () => {
  beforeEach(resetStore)

  it('sets collapsed state to true', () => {
    useTopics.getState().setCollapsed(true)
    expect(useTopics.getState().collapsed).toBe(true)
  })

  it('sets collapsed state to false', () => {
    useTopics.getState().setCollapsed(true)
    useTopics.getState().setCollapsed(false)
    expect(useTopics.getState().collapsed).toBe(false)
  })

  it('persists collapsed=true to localStorage', () => {
    useTopics.getState().setCollapsed(true)
    expect(localStorageMock.getItem('nclaw.sidebar.collapsed')).toBe('true')
  })

  it('persists collapsed=false to localStorage', () => {
    useTopics.getState().setCollapsed(false)
    expect(localStorageMock.getItem('nclaw.sidebar.collapsed')).toBe('false')
  })
})

// ---------------------------------------------------------------------------

describe('useTopics — move', () => {
  beforeEach(resetStore)

  it('calls move_topic with fromId and toParentPath', async () => {
    mockInvoke.mockResolvedValueOnce(undefined) // move_topic
    mockInvoke.mockResolvedValueOnce([])        // subsequent list_topics from load()
    await useTopics.getState().move('a', 'c')
    expect(mockInvoke).toHaveBeenCalledWith('move_topic', {
      fromId: 'a',
      toParentPath: 'c',
    })
  })

  it('reloads topics after move', async () => {
    mockInvoke.mockResolvedValueOnce(undefined)
    mockInvoke.mockResolvedValueOnce([TOPIC_C])
    await useTopics.getState().move('a', 'c')
    expect(useTopics.getState().topics).toEqual([TOPIC_C])
  })

  it('invokes list_topics as second call after move', async () => {
    mockInvoke.mockResolvedValueOnce(undefined)
    mockInvoke.mockResolvedValueOnce([])
    await useTopics.getState().move('a', 'c')
    expect(mockInvoke).toHaveBeenNthCalledWith(2, 'list_topics')
  })
})

// ---------------------------------------------------------------------------

describe('useTopics — search', () => {
  beforeEach(resetStore)

  it('returns search results from invoke("search")', async () => {
    const result = { topics: [TOPIC_A], matched_message_topics: ['a'] }
    mockInvoke.mockResolvedValueOnce(result)
    const res = await useTopics.getState().search('alpha')
    expect(res).toEqual(result)
  })

  it('passes query string to invoke', async () => {
    mockInvoke.mockResolvedValueOnce({ topics: [], matched_message_topics: [] })
    await useTopics.getState().search('hello')
    expect(mockInvoke).toHaveBeenCalledWith('search', { query: 'hello' })
  })

  it('returns empty results for empty query', async () => {
    const result = { topics: [], matched_message_topics: [] }
    mockInvoke.mockResolvedValueOnce(result)
    const res = await useTopics.getState().search('')
    expect(res).toEqual(result)
  })
})

// ---------------------------------------------------------------------------

describe('buildTree', () => {
  it('returns empty array for empty input', () => {
    expect(buildTree([])).toEqual([])
  })

  it('returns a single root node with no children', () => {
    const tree = buildTree([TOPIC_A])
    expect(tree).toHaveLength(1)
    expect(tree[0].topic).toEqual(TOPIC_A)
    expect(tree[0].children).toHaveLength(0)
  })

  it('nests a child under its parent by ltree path', () => {
    const tree = buildTree([TOPIC_A, TOPIC_B])
    expect(tree).toHaveLength(1)
    expect(tree[0].topic.id).toBe('a')
    expect(tree[0].children).toHaveLength(1)
    expect(tree[0].children[0].topic.id).toBe('b')
  })

  it('promotes orphan child to root when parent is missing', () => {
    // TOPIC_B has path 'a.b' but TOPIC_A is absent
    const tree = buildTree([TOPIC_B])
    expect(tree).toHaveLength(1)
    expect(tree[0].topic.id).toBe('b')
  })

  it('handles multiple root nodes', () => {
    const tree = buildTree([TOPIC_A, TOPIC_C])
    expect(tree).toHaveLength(2)
    const ids = tree.map((n) => n.topic.id)
    expect(ids).toContain('a')
    expect(ids).toContain('c')
  })

  it('builds a two-level hierarchy correctly', () => {
    const topics: Topic[] = [
      { id: 'r', path: 'r', name: 'Root', archived: false },
      { id: 'c1', path: 'r.c1', name: 'Child1', archived: false },
      { id: 'c2', path: 'r.c2', name: 'Child2', archived: false },
    ]
    const tree = buildTree(topics)
    expect(tree).toHaveLength(1)
    expect(tree[0].children).toHaveLength(2)
  })

  it('does not mutate input array', () => {
    const topics: Topic[] = [TOPIC_A, TOPIC_B]
    const copy = [...topics]
    buildTree(topics)
    expect(topics).toEqual(copy)
  })
})
