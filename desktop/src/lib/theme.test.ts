import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import {
  ACCENT_PRESETS,
  isValidHex,
  applyTheme,
  loadThemeFromStorage,
  saveTheme,
} from './theme'

// jsdom does not implement window.matchMedia — provide a minimal mock
function mockMatchMedia(prefersDark: boolean) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: query === '(prefers-color-scheme: dark)' ? prefersDark : false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  })
}

describe('ACCENT_PRESETS', () => {
  it('has at least one preset', () => {
    expect(ACCENT_PRESETS.length).toBeGreaterThan(0)
  })

  it('every preset has id, label, and a valid hex', () => {
    for (const p of ACCENT_PRESETS) {
      expect(p.id).toBeTruthy()
      expect(p.label).toBeTruthy()
      expect(isValidHex(p.hex)).toBe(true)
    }
  })

  it('sky preset exists with default accent color', () => {
    const sky = ACCENT_PRESETS.find((p) => p.id === 'sky')
    expect(sky).toBeDefined()
    expect(sky!.hex).toBe('#0ea5e9')
  })
})

describe('isValidHex', () => {
  it('accepts a 6-digit hex with hash', () => {
    expect(isValidHex('#0ea5e9')).toBe(true)
  })

  it('accepts a 6-digit hex without hash', () => {
    expect(isValidHex('0ea5e9')).toBe(true)
  })

  it('accepts an 8-digit hex (with alpha) with hash', () => {
    expect(isValidHex('#0ea5e9ff')).toBe(true)
  })

  it('accepts uppercase hex', () => {
    expect(isValidHex('#FFFFFF')).toBe(true)
  })

  it('rejects a 3-digit shorthand hex', () => {
    expect(isValidHex('#fff')).toBe(false)
  })

  it('rejects hex with invalid characters', () => {
    expect(isValidHex('#gggggg')).toBe(false)
  })

  it('rejects an empty string', () => {
    expect(isValidHex('')).toBe(false)
  })

  it('rejects a plain word', () => {
    expect(isValidHex('red')).toBe(false)
  })
})

describe('applyTheme', () => {
  beforeEach(() => {
    document.documentElement.className = ''
    document.documentElement.style.removeProperty('--accent')
  })

  it('sets dark class when mode is dark', () => {
    mockMatchMedia(false)
    applyTheme('dark', '#0ea5e9')
    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(document.documentElement.classList.contains('light')).toBe(false)
  })

  it('sets light class when mode is light', () => {
    mockMatchMedia(false)
    applyTheme('light', '#0ea5e9')
    expect(document.documentElement.classList.contains('light')).toBe(true)
    expect(document.documentElement.classList.contains('dark')).toBe(false)
  })

  it('resolves system mode to dark when prefers-dark is true', () => {
    mockMatchMedia(true)
    applyTheme('system', '#0ea5e9')
    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(document.documentElement.classList.contains('light')).toBe(false)
  })

  it('resolves system mode to light when prefers-dark is false', () => {
    mockMatchMedia(false)
    applyTheme('system', '#0ea5e9')
    expect(document.documentElement.classList.contains('light')).toBe(true)
    expect(document.documentElement.classList.contains('dark')).toBe(false)
  })

  it('sets --accent CSS variable with hash prefix', () => {
    mockMatchMedia(false)
    applyTheme('light', '#abcdef')
    expect(document.documentElement.style.getPropertyValue('--accent')).toBe('#abcdef')
  })

  it('prepends # to accent that lacks it', () => {
    mockMatchMedia(false)
    applyTheme('light', 'abcdef')
    expect(document.documentElement.style.getPropertyValue('--accent')).toBe('#abcdef')
  })
})

describe('loadThemeFromStorage / saveTheme', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  afterEach(() => {
    localStorage.clear()
  })

  it('returns system mode and default accent when nothing is stored', () => {
    const { mode, accentHex } = loadThemeFromStorage()
    expect(mode).toBe('system')
    expect(accentHex).toBe('#0ea5e9')
  })

  it('round-trips mode and accent via saveTheme / loadThemeFromStorage', () => {
    saveTheme('dark', '#8b5cf6')
    const { mode, accentHex } = loadThemeFromStorage()
    expect(mode).toBe('dark')
    expect(accentHex).toBe('#8b5cf6')
  })

  it('round-trips light mode', () => {
    saveTheme('light', '#10b981')
    const { mode } = loadThemeFromStorage()
    expect(mode).toBe('light')
  })

  it('overwrites a previous save', () => {
    saveTheme('dark', '#0000ff')
    saveTheme('light', '#ff0000')
    const { mode, accentHex } = loadThemeFromStorage()
    expect(mode).toBe('light')
    expect(accentHex).toBe('#ff0000')
  })
})
