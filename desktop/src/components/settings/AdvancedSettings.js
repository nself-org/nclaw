import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Advanced Settings section
import { useEffect, useState } from "react";
import { useSettings } from "../../lib/settings-store";
const LOG_LEVELS = ["error", "warn", "info", "debug", "trace"];
function Toggle({ id, label, description, checked, onChange }) {
    return (_jsxs("div", { className: "flex items-start justify-between gap-4", children: [_jsxs("div", { children: [_jsx("label", { htmlFor: id, className: "text-sm font-medium text-slate-200 cursor-pointer", children: label }), _jsx("p", { className: "text-xs text-slate-500 mt-0.5", children: description })] }), _jsx("button", { id: id, role: "switch", "aria-checked": checked, onClick: () => onChange(!checked), className: `relative inline-flex h-5 w-9 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-sky-500 cursor-pointer ${checked ? "bg-sky-600" : "bg-slate-600"}`, "aria-label": label, children: _jsx("span", { "aria-hidden": "true", className: `inline-block h-4 w-4 transform rounded-full bg-white shadow transition duration-200 ${checked ? "translate-x-4" : "translate-x-0"}` }) })] }));
}
export function AdvancedSettings() {
    const { settings, saveSection } = useSettings();
    const current = settings.advanced;
    const [draft, setDraft] = useState(current);
    const [saved, setSaved] = useState(false);
    const [error, setError] = useState(null);
    useEffect(() => {
        setDraft(current);
    }, [current]);
    const handleSave = async () => {
        setError(null);
        try {
            await saveSection("advanced", draft);
            setSaved(true);
            setTimeout(() => setSaved(false), 2000);
        }
        catch (e) {
            setError(String(e));
        }
    };
    return (_jsxs("section", { "aria-labelledby": "advanced-heading", children: [_jsx("h2", { id: "advanced-heading", className: "text-lg font-semibold text-slate-100 mb-4", children: "Advanced" }), _jsxs("div", { className: "mb-5", children: [_jsx("label", { htmlFor: "log-level", className: "block text-sm font-medium text-slate-300 mb-1", children: "Log level" }), _jsx("p", { className: "text-xs text-slate-500 mb-2", children: "Controls verbosity of the local log file. Restart required for changes to take effect." }), _jsx("select", { id: "log-level", value: draft.log_level, onChange: (e) => setDraft((d) => ({
                            ...d,
                            log_level: e.target.value,
                        })), className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Log level", children: LOG_LEVELS.map((l) => (_jsx("option", { value: l, children: l.charAt(0).toUpperCase() + l.slice(1) }, l))) })] }), _jsxs("div", { className: "space-y-4 mb-6", children: [_jsx(Toggle, { id: "toggle-telemetry", label: "Usage telemetry", description: "Send anonymous crash reports and usage statistics to help improve \u0273Claw.", checked: draft.telemetry, onChange: (v) => setDraft((d) => ({ ...d, telemetry: v })) }), _jsx(Toggle, { id: "toggle-check-updates", label: "Check for updates", description: "Automatically check for new \u0273Claw Desktop releases on startup.", checked: draft.check_updates, onChange: (v) => setDraft((d) => ({ ...d, check_updates: v })) })] }), error && (_jsx("p", { role: "alert", className: "mb-3 text-sm text-red-400", children: error })), _jsx("button", { onClick: handleSave, className: "rounded-md bg-sky-600 hover:bg-sky-500 text-white px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Save advanced settings", children: saved ? "Saved" : "Save" })] }));
}
