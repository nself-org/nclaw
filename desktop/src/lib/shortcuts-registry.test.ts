import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import {
  DEFAULT_SHORTCUTS,
  getShortcuts,
  setShortcut,
  resetShortcuts,
  resetShortcut,
} from './shortcuts-registry'

describe('DEFAULT_SHORTCUTS', () => {
  it('is non-empty', () => {
    expect(DEFAULT_SHORTCUTS.length).toBeGreaterThan(0)
  })

  it('every shortcut has required fields', () => {
    for (const s of DEFAULT_SHORTCUTS) {
      expect(s.id).toBeTruthy()
      expect(s.label).toBeTruthy()
      expect(s.section).toMatch(/^(Chat|Navigation|Window|Editing)$/)
      expect(s.default.mac).toBeTruthy()
      expect(s.default.other).toBeTruthy()
    }
  })

  it('all shortcut ids are unique — no collision', () => {
    const ids = DEFAULT_SHORTCUTS.map((s) => s.id)
    const unique = new Set(ids)
    expect(unique.size).toBe(ids.length)
  })

  it('no two shortcuts share the same mac combo — no collision on mac platform', () => {
    const macCombos = DEFAULT_SHORTCUTS.map((s) => s.default.mac)
    const uniqueCombos = new Set(macCombos)
    // Duplicate check: if any combo appears twice the set shrinks
    expect(uniqueCombos.size).toBe(macCombos.length)
  })

  it('no two shortcuts share the same other-platform combo', () => {
    const otherCombos = DEFAULT_SHORTCUTS.map((s) => s.default.other)
    const uniqueCombos = new Set(otherCombos)
    expect(uniqueCombos.size).toBe(otherCombos.length)
  })

  it('includes essential shortcuts: new-chat, send, palette', () => {
    const ids = DEFAULT_SHORTCUTS.map((s) => s.id)
    expect(ids).toContain('new-chat')
    expect(ids).toContain('send')
    expect(ids).toContain('palette')
  })

  it('new-chat uses ⌘N on mac and Ctrl+N on other', () => {
    const s = DEFAULT_SHORTCUTS.find((d) => d.id === 'new-chat')!
    expect(s.default.mac).toBe('⌘N')
    expect(s.default.other).toBe('Ctrl+N')
  })

  it('no shortcut has a current override in the default list', () => {
    for (const s of DEFAULT_SHORTCUTS) {
      expect(s.current).toBeUndefined()
    }
  })
})

describe('getShortcuts', () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => localStorage.clear())

  it('returns DEFAULT_SHORTCUTS when nothing is stored', () => {
    const shortcuts = getShortcuts()
    expect(shortcuts).toHaveLength(DEFAULT_SHORTCUTS.length)
    expect(shortcuts.map((s) => s.id)).toEqual(DEFAULT_SHORTCUTS.map((s) => s.id))
  })

  it('returns defaults without current field when no overrides', () => {
    const shortcuts = getShortcuts()
    for (const s of shortcuts) {
      expect(s.current).toBeUndefined()
    }
  })

  it('merges stored override for a known id', () => {
    const override = { mac: '⌘⌥N', other: 'Ctrl+Alt+N' }
    localStorage.setItem('nclaw.shortcuts.custom', JSON.stringify({ 'new-chat': override }))

    const shortcuts = getShortcuts()
    const newChat = shortcuts.find((s) => s.id === 'new-chat')!
    expect(newChat.current).toEqual(override)
  })

  it('leaves unaffected shortcuts without a current field', () => {
    localStorage.setItem(
      'nclaw.shortcuts.custom',
      JSON.stringify({ 'new-chat': { mac: '⌘⌥N', other: 'Ctrl+Alt+N' } })
    )
    const shortcuts = getShortcuts()
    const send = shortcuts.find((s) => s.id === 'send')!
    expect(send.current).toBeUndefined()
  })

  it('falls back to DEFAULT_SHORTCUTS on malformed JSON', () => {
    localStorage.setItem('nclaw.shortcuts.custom', '{INVALID_JSON')
    const shortcuts = getShortcuts()
    expect(shortcuts).toHaveLength(DEFAULT_SHORTCUTS.length)
    // No current field should exist
    for (const s of shortcuts) {
      expect(s.current).toBeUndefined()
    }
  })

  it('ignores stored overrides for unknown ids', () => {
    localStorage.setItem(
      'nclaw.shortcuts.custom',
      JSON.stringify({ 'nonexistent-id': { mac: '⌘X', other: 'Ctrl+X' } })
    )
    const shortcuts = getShortcuts()
    expect(shortcuts).toHaveLength(DEFAULT_SHORTCUTS.length)
  })
})

describe('setShortcut', () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => localStorage.clear())

  it('persists a new override to localStorage', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    const stored = JSON.parse(localStorage.getItem('nclaw.shortcuts.custom')!)
    expect(stored['new-chat']).toEqual({ mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
  })

  it('overrides an existing stored value', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    setShortcut('new-chat', { mac: '⌘⌥M', other: 'Ctrl+Alt+M' })
    const stored = JSON.parse(localStorage.getItem('nclaw.shortcuts.custom')!)
    expect(stored['new-chat']).toEqual({ mac: '⌘⌥M', other: 'Ctrl+Alt+M' })
  })

  it('adding a second override preserves the first', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    setShortcut('send', { mac: '⌘Return', other: 'Ctrl+Enter' })
    const stored = JSON.parse(localStorage.getItem('nclaw.shortcuts.custom')!)
    expect(stored['new-chat']).toBeDefined()
    expect(stored['send']).toBeDefined()
  })

  it('set + getShortcuts reflects the override', () => {
    setShortcut('palette', { mac: '⌘P', other: 'Ctrl+P' })
    const shortcuts = getShortcuts()
    const palette = shortcuts.find((s) => s.id === 'palette')!
    expect(palette.current).toEqual({ mac: '⌘P', other: 'Ctrl+P' })
    // default is preserved
    expect(palette.default.mac).toBe('⌘K')
  })
})

describe('resetShortcuts', () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => localStorage.clear())

  it('clears all stored overrides', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    setShortcut('send', { mac: '⌘Return', other: 'Ctrl+Enter' })
    resetShortcuts()
    expect(localStorage.getItem('nclaw.shortcuts.custom')).toBeNull()
  })

  it('after reset, getShortcuts returns no current fields', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    resetShortcuts()
    const shortcuts = getShortcuts()
    for (const s of shortcuts) {
      expect(s.current).toBeUndefined()
    }
  })

  it('is idempotent — calling twice does not throw', () => {
    expect(() => {
      resetShortcuts()
      resetShortcuts()
    }).not.toThrow()
  })
})

describe('resetShortcut (single)', () => {
  beforeEach(() => localStorage.clear())
  afterEach(() => localStorage.clear())

  it('removes only the targeted shortcut override', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    setShortcut('send', { mac: '⌘Return', other: 'Ctrl+Enter' })
    resetShortcut('new-chat')
    const stored = JSON.parse(localStorage.getItem('nclaw.shortcuts.custom')!)
    expect(stored['new-chat']).toBeUndefined()
    expect(stored['send']).toBeDefined()
  })

  it('removes the key entirely when it is the last override', () => {
    setShortcut('new-chat', { mac: '⌘⌥N', other: 'Ctrl+Alt+N' })
    resetShortcut('new-chat')
    expect(localStorage.getItem('nclaw.shortcuts.custom')).toBeNull()
  })

  it('no-ops gracefully when there are no stored overrides', () => {
    expect(() => resetShortcut('new-chat')).not.toThrow()
  })

  it('no-ops gracefully for an id with no override', () => {
    setShortcut('send', { mac: '⌘Return', other: 'Ctrl+Enter' })
    expect(() => resetShortcut('new-chat')).not.toThrow()
    const stored = JSON.parse(localStorage.getItem('nclaw.shortcuts.custom')!)
    expect(stored['send']).toBeDefined()
  })
})
