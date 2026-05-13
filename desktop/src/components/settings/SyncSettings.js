import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Sync Settings section
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSettings, maskKey } from "../../lib/settings-store";
export function SyncSettings() {
    const { settings, saveSection } = useSettings();
    const current = settings.sync;
    const [draft, setDraft] = useState({
        server_url: current.server_url,
        license_key_raw: "",
    });
    const [saved, setSaved] = useState(false);
    const [saveError, setSaveError] = useState(null);
    const [testState, setTestState] = useState("idle");
    const [testMessage, setTestMessage] = useState("");
    useEffect(() => {
        setDraft((d) => ({ ...d, server_url: current.server_url }));
    }, [current.server_url]);
    const handleSave = async () => {
        setSaveError(null);
        try {
            const license_key_masked = draft.license_key_raw
                ? maskKey(draft.license_key_raw)
                : current.license_key_masked;
            await saveSection("sync", {
                server_url: draft.server_url,
                license_key_masked,
            });
            setDraft((d) => ({ ...d, license_key_raw: "" }));
            setSaved(true);
            setTimeout(() => setSaved(false), 2000);
        }
        catch (e) {
            setSaveError(String(e));
        }
    };
    const handleTestConnection = async () => {
        setTestState("testing");
        setTestMessage("");
        try {
            const ok = await invoke("test_sync_connection", {
                url: draft.server_url,
                key: draft.license_key_raw || "",
            });
            setTestState(ok ? "ok" : "fail");
            setTestMessage(ok ? "Connection successful." : "Connection failed. Check URL and key.");
        }
        catch (e) {
            setTestState("fail");
            setTestMessage(String(e));
        }
    };
    return (_jsxs("section", { "aria-labelledby": "sync-heading", children: [_jsx("h2", { id: "sync-heading", className: "text-lg font-semibold text-slate-100 mb-4", children: "Sync & License" }), _jsxs("div", { className: "mb-4", children: [_jsx("label", { htmlFor: "sync-server-url", className: "block text-sm font-medium text-slate-300 mb-1", children: "nSelf server URL" }), _jsx("input", { id: "sync-server-url", type: "url", value: draft.server_url, onChange: (e) => setDraft((d) => ({ ...d, server_url: e.target.value })), placeholder: "https://your-nself-server.example.com", className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder:text-slate-600", "aria-label": "nSelf server URL" })] }), _jsxs("div", { className: "mb-4", children: [_jsx("label", { htmlFor: "sync-license-key", className: "block text-sm font-medium text-slate-300 mb-1", children: "License key" }), _jsx("input", { id: "sync-license-key", type: "password", value: draft.license_key_raw, onChange: (e) => setDraft((d) => ({ ...d, license_key_raw: e.target.value })), placeholder: current.license_key_masked || "nself_pro_…", className: "w-full rounded-md bg-slate-800 border border-slate-700 text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder:text-slate-600", autoComplete: "off", "aria-label": "License key (masked)" }), current.license_key_masked && !draft.license_key_raw && (_jsxs("p", { className: "mt-1 text-xs text-slate-500", children: ["Saved key: ", _jsx("span", { className: "font-mono", children: current.license_key_masked })] }))] }), _jsxs("div", { className: "flex items-center gap-3 mb-4", children: [_jsx("button", { onClick: handleTestConnection, disabled: !draft.server_url || testState === "testing", className: "rounded-md bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-slate-200 px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Test sync connection", children: testState === "testing" ? "Testing…" : "Test connection" }), testState !== "idle" && testState !== "testing" && (_jsx("span", { role: "status", className: `text-sm ${testState === "ok" ? "text-green-400" : "text-red-400"}`, children: testMessage }))] }), saveError && (_jsx("p", { role: "alert", className: "mb-3 text-sm text-red-400", children: saveError })), _jsx("button", { onClick: handleSave, className: "rounded-md bg-sky-600 hover:bg-sky-500 text-white px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Save sync settings", children: saved ? "Saved" : "Save" })] }));
}
