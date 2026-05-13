import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Provider Settings section
import { useState } from "react";
import { useSettings, maskKey } from "../../lib/settings-store";
const PROVIDERS = [
    { id: "local-llamacpp", label: "Local (llama.cpp)", requiresKey: false, defaultUrl: "http://127.0.0.1:8080" },
    { id: "ollama-sidecar", label: "Ollama sidecar", requiresKey: false, defaultUrl: "http://127.0.0.1:11434" },
    { id: "openai", label: "OpenAI", requiresKey: true, defaultUrl: "https://api.openai.com/v1" },
    { id: "anthropic", label: "Anthropic", requiresKey: true, defaultUrl: "https://api.anthropic.com" },
    { id: "openrouter", label: "OpenRouter", requiresKey: true, defaultUrl: "https://openrouter.ai/api/v1" },
];
export function ProviderSettings() {
    const { settings, saveSection } = useSettings();
    const current = settings.provider;
    const [draft, setDraft] = useState({
        id: current.id,
        base_url: current.base_url,
        api_key_raw: "",
    });
    const [saved, setSaved] = useState(false);
    const [error, setError] = useState(null);
    const selected = PROVIDERS.find((p) => p.id === draft.id) ?? PROVIDERS[0];
    const handleProviderChange = (id) => {
        const p = PROVIDERS.find((pp) => pp.id === id);
        setDraft({ id, base_url: p.defaultUrl, api_key_raw: "" });
        setSaved(false);
    };
    const handleSave = async () => {
        setError(null);
        try {
            const api_key_masked = draft.api_key_raw ? maskKey(draft.api_key_raw) : current.api_key_masked;
            await saveSection("provider", {
                id: draft.id,
                base_url: draft.base_url,
                api_key_masked,
            });
            setDraft((d) => ({ ...d, api_key_raw: "" }));
            setSaved(true);
            setTimeout(() => setSaved(false), 2000);
        }
        catch (e) {
            setError(String(e));
        }
    };
    return (_jsxs("section", { "aria-labelledby": "provider-heading", children: [_jsx("h2", { id: "provider-heading", className: "text-lg font-semibold text-slate-100 mb-4", children: "AI Provider" }), _jsxs("div", { className: "mb-4", children: [_jsx("label", { htmlFor: "provider-select", className: "block text-sm font-medium text-slate-300 mb-1", children: "Provider" }), _jsx("select", { id: "provider-select", value: draft.id, onChange: (e) => handleProviderChange(e.target.value), className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Select AI provider", children: PROVIDERS.map((p) => (_jsx("option", { value: p.id, children: p.label }, p.id))) })] }), _jsxs("div", { className: "mb-4", children: [_jsx("label", { htmlFor: "provider-base-url", className: "block text-sm font-medium text-slate-300 mb-1", children: "API Base URL" }), _jsx("input", { id: "provider-base-url", type: "url", value: draft.base_url, onChange: (e) => setDraft((d) => ({ ...d, base_url: e.target.value })), placeholder: selected.defaultUrl, className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder:text-slate-600", "aria-label": "API base URL" })] }), selected.requiresKey && (_jsxs("div", { className: "mb-4", children: [_jsx("label", { htmlFor: "provider-api-key", className: "block text-sm font-medium text-slate-300 mb-1", children: "API Key" }), _jsx("input", { id: "provider-api-key", type: "password", value: draft.api_key_raw, onChange: (e) => setDraft((d) => ({ ...d, api_key_raw: e.target.value })), placeholder: current.api_key_masked || "Enter API key", className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder:text-slate-600", autoComplete: "off", "aria-label": "API key (masked)" }), current.api_key_masked && !draft.api_key_raw && (_jsxs("p", { className: "mt-1 text-xs text-slate-500", children: ["Saved key: ", _jsx("span", { className: "font-mono", children: current.api_key_masked })] }))] })), error && (_jsx("p", { role: "alert", className: "mb-3 text-sm text-red-400", children: error })), _jsx("button", { onClick: handleSave, className: "rounded-md bg-sky-600 hover:bg-sky-500 text-white px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Save provider settings", children: saved ? "Saved" : "Save" })] }));
}
