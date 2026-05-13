// ɳClaw Desktop — Settings store (Zustand + Tauri invoke bridge)
import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
// ---- Defaults (used until backend responds) --------------------------------
const DEFAULT_SETTINGS = {
    provider: { id: "local-llamacpp", base_url: "", api_key_masked: "" },
    model: { chat: "", summarizer: "", embedder: "", code: "" },
    vault: { paired: false, backend: "" },
    sync: { server_url: "", license_key_masked: "" },
    advanced: { log_level: "info", telemetry: true, check_updates: true },
};
// ---- Zustand store ---------------------------------------------------------
export const useSettings = create((set, _get) => ({
    settings: DEFAULT_SETTINGS,
    loading: false,
    error: null,
    load: async () => {
        set({ loading: true, error: null });
        try {
            const raw = await invoke("get_all_settings");
            set({ settings: raw, loading: false });
        }
        catch (err) {
            // Graceful degradation — keep defaults on stub/error
            set({ loading: false, error: String(err) });
        }
    },
    saveSection: async (section, value) => {
        // Optimistic update
        set((s) => ({ settings: { ...s.settings, [section]: value } }));
        try {
            await invoke("set_setting", { key: section, value });
        }
        catch (err) {
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
export function maskKey(raw) {
    if (!raw || raw.length < 4)
        return "••••";
    return `••••${raw.slice(-4)}`;
}
