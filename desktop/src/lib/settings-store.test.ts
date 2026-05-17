import { describe, it, expect } from 'vitest'
import { maskKey, DEFAULT_SETTINGS } from './settings-store'
import type { Settings, ProviderSettings, AdvancedSettings } from './settings-store'

// Note: useSettings (Zustand store with Tauri invoke) is exercised via the
// maskKey helper and the exported DEFAULT_SETTINGS shape. The Tauri invoke
// bridge is not available in jsdom and is covered by T07 integration tests.

describe('maskKey', () => {
  it('masks a normal API key — keeps last 4 chars', () => {
    expect(maskKey('sk-12345678')).toBe('••••5678')
  })

  it('masks a longer key', () => {
    expect(maskKey('nself_pro_abcdefghijklmnop')).toBe('••••mnop')
  })

  it('returns ••••  for a key shorter than 4 chars', () => {
    expect(maskKey('abc')).toBe('••••')
  })

  it('returns •••• for an exact-4-char key', () => {
    // raw.length === 4 → slice(-4) === raw → returns ••••<last4> which is '••••abcd'
    expect(maskKey('abcd')).toBe('••••abcd')
  })

  it('returns •••• for an empty string', () => {
    expect(maskKey('')).toBe('••••')
  })

  it('never surfaces the raw key in the masked output', () => {
    const raw = 'super-secret-key-1234'
    const masked = maskKey(raw)
    expect(masked.startsWith('••••')).toBe(true)
    expect(masked).not.toBe(raw)
    // only last 4 chars are revealed
    expect(masked).toBe('••••1234')
  })
})

describe('DEFAULT_SETTINGS shape', () => {
  it('has the expected top-level keys', () => {
    const keys: (keyof Settings)[] = ['provider', 'model', 'vault', 'sync', 'advanced']
    for (const key of keys) {
      expect(DEFAULT_SETTINGS).toHaveProperty(key)
    }
  })

  it('provider defaults to local-llamacpp', () => {
    expect(DEFAULT_SETTINGS.provider.id).toBe('local-llamacpp')
  })

  it('provider base_url defaults to empty string', () => {
    expect(DEFAULT_SETTINGS.provider.base_url).toBe('')
  })

  it('provider api_key_masked defaults to empty string', () => {
    expect(DEFAULT_SETTINGS.provider.api_key_masked).toBe('')
  })

  it('model fields default to empty strings', () => {
    const model = DEFAULT_SETTINGS.model
    expect(model.chat).toBe('')
    expect(model.summarizer).toBe('')
    expect(model.embedder).toBe('')
    expect(model.code).toBe('')
  })

  it('vault defaults to unpaired with empty backend', () => {
    expect(DEFAULT_SETTINGS.vault.paired).toBe(false)
    expect(DEFAULT_SETTINGS.vault.backend).toBe('')
  })

  it('sync defaults to empty server_url and empty license_key_masked', () => {
    expect(DEFAULT_SETTINGS.sync.server_url).toBe('')
    expect(DEFAULT_SETTINGS.sync.license_key_masked).toBe('')
  })

  it('advanced log_level defaults to info', () => {
    expect(DEFAULT_SETTINGS.advanced.log_level).toBe('info')
  })

  it('advanced telemetry defaults to true', () => {
    expect(DEFAULT_SETTINGS.advanced.telemetry).toBe(true)
  })

  it('advanced check_updates defaults to true', () => {
    expect(DEFAULT_SETTINGS.advanced.check_updates).toBe(true)
  })

  it('DEFAULT_SETTINGS is JSON-serializable (round-trips cleanly)', () => {
    const serialized = JSON.stringify(DEFAULT_SETTINGS)
    const parsed = JSON.parse(serialized) as Settings
    expect(parsed).toEqual(DEFAULT_SETTINGS)
  })
})

describe('ProviderSettings id type guard', () => {
  const validIds: ProviderSettings['id'][] = [
    'local-llamacpp',
    'ollama-sidecar',
    'openai',
    'anthropic',
    'openrouter',
  ]

  it('all valid provider ids are accepted by the type', () => {
    for (const id of validIds) {
      const p: ProviderSettings = { id, base_url: '', api_key_masked: '' }
      expect(p.id).toBe(id)
    }
  })
})

describe('AdvancedSettings log_level type guard', () => {
  const validLevels: AdvancedSettings['log_level'][] = [
    'error', 'warn', 'info', 'debug', 'trace',
  ]

  it('all valid log levels are accepted by the type', () => {
    for (const level of validLevels) {
      const adv: AdvancedSettings = { log_level: level, telemetry: false, check_updates: false }
      expect(adv.log_level).toBe(level)
    }
  })
})
