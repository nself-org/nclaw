/**
 * Unit tests for useSettings (zustand store) — covers load, saveSection, patch
 * store actions with deterministic Tauri invoke mocks.
 *
 * T06 covers the maskKey helper and DEFAULT_SETTINGS shape constants.
 * T07 (this file) covers the store's async actions that call Tauri IPC.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

// --- Mock @tauri-apps/api/core before importing the store ------------------
const { mockInvoke } = vi.hoisted(() => ({ mockInvoke: vi.fn() }))
vi.mock('@tauri-apps/api/core', () => ({ invoke: mockInvoke }))

import { useSettings, DEFAULT_SETTINGS } from './settings-store'
import type { Settings } from './settings-store'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MOCK_SETTINGS: Settings = {
  provider: { id: 'openai', base_url: 'https://api.openai.com', api_key_masked: '••••abcd' },
  model: { chat: 'gpt-4o', summarizer: 'gpt-4o-mini', embedder: 'text-embedding-3-small', code: 'gpt-4o' },
  vault: { paired: true, backend: 'https://vault.example.com' },
  sync: { server_url: 'https://nself.example.com', license_key_masked: '••••1234' },
  advanced: { log_level: 'debug', telemetry: false, check_updates: false },
}

function resetStore() {
  // Partial update only — do NOT use replace=true which would strip actions in zustand v5
  useSettings.setState({
    settings: { ...DEFAULT_SETTINGS },
    loading: false,
    error: null,
  })
  mockInvoke.mockReset()
}

// ---------------------------------------------------------------------------

describe('useSettings — load', () => {
  beforeEach(resetStore)

  it('sets loading=true then loading=false after success', async () => {
    let loadingDuringCall = false
    mockInvoke.mockImplementationOnce(async () => {
      loadingDuringCall = useSettings.getState().loading
      return MOCK_SETTINGS
    })
    await useSettings.getState().load()
    expect(loadingDuringCall).toBe(true)
    expect(useSettings.getState().loading).toBe(false)
  })

  it('calls get_all_settings via invoke', async () => {
    mockInvoke.mockResolvedValueOnce(MOCK_SETTINGS)
    await useSettings.getState().load()
    expect(mockInvoke).toHaveBeenCalledWith('get_all_settings')
  })

  it('stores backend settings on success', async () => {
    mockInvoke.mockResolvedValueOnce(MOCK_SETTINGS)
    await useSettings.getState().load()
    expect(useSettings.getState().settings).toEqual(MOCK_SETTINGS)
  })

  it('clears error field on success', async () => {
    // Pre-set an error
    useSettings.setState({ error: 'prior error' })
    mockInvoke.mockResolvedValueOnce(MOCK_SETTINGS)
    await useSettings.getState().load()
    expect(useSettings.getState().error).toBeNull()
  })

  it('keeps DEFAULT_SETTINGS on invoke failure (graceful degradation)', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('IPC error'))
    await useSettings.getState().load()
    expect(useSettings.getState().settings).toEqual(DEFAULT_SETTINGS)
  })

  it('sets error message on invoke failure', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('backend unavailable'))
    await useSettings.getState().load()
    expect(useSettings.getState().error).toContain('backend unavailable')
  })

  it('sets loading=false on failure', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('oops'))
    await useSettings.getState().load()
    expect(useSettings.getState().loading).toBe(false)
  })
})

// ---------------------------------------------------------------------------

describe('useSettings — saveSection', () => {
  beforeEach(resetStore)

  it('applies optimistic update to state immediately', async () => {
    const newProvider = { id: 'anthropic' as const, base_url: '', api_key_masked: '••••zzzz' }
    mockInvoke.mockResolvedValueOnce(undefined)
    await useSettings.getState().saveSection('provider', newProvider)
    expect(useSettings.getState().settings.provider).toEqual(newProvider)
  })

  it('calls invoke("set_setting") with section key and value', async () => {
    const newAdvanced = { log_level: 'debug' as const, telemetry: false, check_updates: true }
    mockInvoke.mockResolvedValueOnce(undefined)
    await useSettings.getState().saveSection('advanced', newAdvanced)
    expect(mockInvoke).toHaveBeenCalledWith('set_setting', {
      key: 'advanced',
      value: newAdvanced,
    })
  })

  it('saves model section correctly', async () => {
    const newModel = { chat: 'gpt-4o', summarizer: 'gpt-4o-mini', embedder: 'text-embedding-3-small', code: 'gpt-4o' }
    mockInvoke.mockResolvedValueOnce(undefined)
    await useSettings.getState().saveSection('model', newModel)
    expect(useSettings.getState().settings.model).toEqual(newModel)
  })

  it('does not revert optimistic state on success', async () => {
    const newVault = { paired: true, backend: 'https://vault.example.com' }
    mockInvoke.mockResolvedValueOnce(undefined)
    await useSettings.getState().saveSection('vault', newVault)
    expect(useSettings.getState().settings.vault).toEqual(newVault)
  })

  it('sets error on invoke failure', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('write failed'))
    await useSettings.getState().saveSection('advanced', DEFAULT_SETTINGS.advanced)
    expect(useSettings.getState().error).toContain('write failed')
  })

  it('preserves optimistic state even on invoke failure', async () => {
    const newProvider = { id: 'ollama-sidecar' as const, base_url: 'http://localhost:11434', api_key_masked: '' }
    mockInvoke.mockRejectedValueOnce(new Error('backend error'))
    await useSettings.getState().saveSection('provider', newProvider)
    // Optimistic update already applied — spec says rollback sets error but keeps state
    expect(useSettings.getState().settings.provider.id).toBe('ollama-sidecar')
  })

  it('only changes the targeted section, not others', async () => {
    const newSync = { server_url: 'https://custom.nself.io', license_key_masked: '••••9999' }
    mockInvoke.mockResolvedValueOnce(undefined)
    await useSettings.getState().saveSection('sync', newSync)
    // Other sections must remain at defaults
    expect(useSettings.getState().settings.model).toEqual(DEFAULT_SETTINGS.model)
    expect(useSettings.getState().settings.provider).toEqual(DEFAULT_SETTINGS.provider)
  })
})

// ---------------------------------------------------------------------------

describe('useSettings — patch', () => {
  beforeEach(resetStore)

  it('applies a partial update to a section', () => {
    useSettings.getState().patch('advanced', { telemetry: false })
    expect(useSettings.getState().settings.advanced.telemetry).toBe(false)
    // Other fields preserved
    expect(useSettings.getState().settings.advanced.log_level).toBe('info')
    expect(useSettings.getState().settings.advanced.check_updates).toBe(true)
  })

  it('merges partial patch with existing section values', () => {
    useSettings.getState().patch('model', { chat: 'claude-3-5-sonnet' })
    const { model } = useSettings.getState().settings
    expect(model.chat).toBe('claude-3-5-sonnet')
    expect(model.summarizer).toBe('')
    expect(model.embedder).toBe('')
    expect(model.code).toBe('')
  })

  it('does not invoke any Tauri command (local only)', () => {
    useSettings.getState().patch('vault', { paired: true })
    expect(mockInvoke).not.toHaveBeenCalled()
  })

  it('patches vault section — paired flag', () => {
    expect(useSettings.getState().settings.vault.paired).toBe(false)
    useSettings.getState().patch('vault', { paired: true })
    expect(useSettings.getState().settings.vault.paired).toBe(true)
  })

  it('patches sync section — server_url', () => {
    useSettings.getState().patch('sync', { server_url: 'https://nself.corp' })
    expect(useSettings.getState().settings.sync.server_url).toBe('https://nself.corp')
    expect(useSettings.getState().settings.sync.license_key_masked).toBe('')
  })

  it('only changes the targeted section, leaves others intact', () => {
    useSettings.getState().patch('provider', { api_key_masked: '••••efgh' })
    expect(useSettings.getState().settings.model).toEqual(DEFAULT_SETTINGS.model)
    expect(useSettings.getState().settings.advanced).toEqual(DEFAULT_SETTINGS.advanced)
  })

  it('successive patches accumulate correctly', () => {
    useSettings.getState().patch('advanced', { telemetry: false })
    useSettings.getState().patch('advanced', { check_updates: false })
    const { advanced } = useSettings.getState().settings
    expect(advanced.telemetry).toBe(false)
    expect(advanced.check_updates).toBe(false)
    expect(advanced.log_level).toBe('info')
  })
})
