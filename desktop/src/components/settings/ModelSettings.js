import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Model Settings section
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge } from "../tier-badge";
import { useSettings } from "../../lib/settings-store";
const ROLES = [
    { key: "chat", label: "Chat", description: "Primary conversational model" },
    { key: "summarizer", label: "Summarizer", description: "Used for context compression and topic labeling" },
    { key: "embedder", label: "Embedder", description: "Vector embeddings for memory search" },
    { key: "code", label: "Code", description: "Code generation and explanation" },
];
export function ModelSettings() {
    const { settings, saveSection } = useSettings();
    const [models, setModels] = useState([]);
    const [draft, setDraft] = useState(settings.model);
    const [saved, setSaved] = useState(false);
    const [error, setError] = useState(null);
    const [loading, setLoading] = useState(true);
    useEffect(() => {
        invoke("list_models")
            .then((m) => setModels(m))
            .catch(() => setModels([]))
            .finally(() => setLoading(false));
    }, []);
    // Sync draft when store updates
    useEffect(() => {
        setDraft(settings.model);
    }, [settings.model]);
    const handleSave = async () => {
        setError(null);
        try {
            await saveSection("model", draft);
            setSaved(true);
            setTimeout(() => setSaved(false), 2000);
        }
        catch (e) {
            setError(String(e));
        }
    };
    const selectedModel = (id) => models.find((m) => m.id === id);
    return (_jsxs("section", { "aria-labelledby": "model-heading", children: [_jsx("h2", { id: "model-heading", className: "text-lg font-semibold text-slate-100 mb-4", children: "Model Selection" }), loading ? (_jsx("p", { className: "text-sm text-slate-500", children: "Loading available models\u2026" })) : (_jsx("div", { className: "space-y-5", children: ROLES.map((role) => {
                    const chosen = selectedModel(draft[role.key]);
                    return (_jsxs("div", { children: [_jsxs("div", { className: "flex items-center justify-between mb-1", children: [_jsx("label", { htmlFor: `model-${role.key}`, className: "text-sm font-medium text-slate-300", children: role.label }), chosen && (_jsx(TierBadge, { tier: chosen.tier, isOverride: !chosen.is_default, className: "ml-2" }))] }), _jsx("p", { className: "text-xs text-slate-500 mb-1", children: role.description }), _jsxs("select", { id: `model-${role.key}`, value: draft[role.key], onChange: (e) => setDraft((d) => ({ ...d, [role.key]: e.target.value })), className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": `Select ${role.label} model`, children: [_jsx("option", { value: "", children: "\u2014 Auto (device default) \u2014" }), models.map((m) => (_jsx("option", { value: m.id, children: m.label }, m.id)))] })] }, role.key));
                }) })), error && (_jsx("p", { role: "alert", className: "mt-4 text-sm text-red-400", children: error })), _jsx("button", { onClick: handleSave, disabled: loading, className: "mt-5 rounded-md bg-sky-600 hover:bg-sky-500 disabled:opacity-50 text-white px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Save model settings", children: saved ? "Saved" : "Save" })] }));
}
