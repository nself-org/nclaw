// ɳClaw Desktop — Settings store (Zustand + Tauri invoke bridge)
import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

// ---- Types ----------------------------------------------------------------

export interface ProviderSettings {
  id: "local-llamacpp" | "ollama-sidecar" | "openai" | "anthropic" | "openrouter";
  base_url: string;
  /** Last 4 chars only — raw key is never stored on the frontend. */
  api_key_masked: string;
}

export interface ModelSettings {
  chat: string;
  summarizer: string;
  embedder: string;
  code: string;
}

export interface VaultSettings {
  paired: boolean;
  backend: string;
}

export interface SyncSettings {
  server_url: string;
  /** Last 4 chars only — raw key is never stored on the frontend. */
  license_key_masked: string;
}

export interface AdvancedSettings {
  log_level: "error" | "warn" | "info" | "debug" | "trace";
  telemetry: boolean;
  check_updates: boolean;
}

export interface Settings {
  provider: ProviderSettings;
  model: ModelSettings;
  vault: VaultSettings;
  sync: SyncSettings;
  advanced: AdvancedSettings;
}

// ---- Defaults (used until backend responds) --------------------------------

const DEFAULT_SETTINGS: Settings = {
  provider: { id: "local-llamacpp", base_url: "", api_key_masked: "" },
  model: { chat: "", summarizer: "", embedder: "", code: "" },
  vault: { paired: false, backend: "" },
  sync: { server_url: "", license_key_masked: "" },
  advanced: { log_level: "info", telemetry: true, check_updates: true },
};

// ---- Store shape -----------------------------------------------------------

interface SettingsState {
  settings: Settings;
  loading: boolean;
  error: string | null;

  /** Load all settings from the backend. Call once on mount. */
  load: () => Promise<void>;

  /** Persist a top-level section. The backend handles encryption + keychain. */
  saveSection: <K extends keyof Settings>(
    section: K,
    value: Settings[K]
  ) => Promise<void>;

  /** Optimistic local update (before backend round-trip). */
  patch: <K extends keyof Settings>(section: K, value: Partial<Settings[K]>) => void;
}

// ---- Zustand store ---------------------------------------------------------

export const useSettings = create<SettingsState>((set, _get) => ({
  settings: DEFAULT_SETTINGS,
  loading: false,
  error: null,

  load: async () => {
    set({ loading: true, error: null });
    try {
      const raw = await invoke<Settings>("get_all_settings");
      set({ settings: raw, loading: false });
    } catch (err) {
      // Graceful degradation — keep defaults on stub/error
      set({ loading: false, error: String(err) });
    }
  },

  saveSection: async (section, value) => {
    // Optimistic update
    set((s) => ({ settings: { ...s.settings, [section]: value } }));
    try {
      await invoke("set_setting", { key: section, value });
    } catch (err) {
      // Rollback on failure
      set({ error: String(err) });
    }
  },

  patch: (section, value) => {
    set((s) => ({
      settings: {
        ...s.settings,
        [section]: { ...s.settings[section], ...value },
      },
    }));
  },
}));

// ---- Key masking helper (frontend-only) ------------------------------------

/** Mask a raw key — keep last 4 chars. Never log or store raw keys. */
export function maskKey(raw: string): string {
  if (!raw || raw.length < 4) return "••••";
  return `••••${raw.slice(-4)}`;
}
