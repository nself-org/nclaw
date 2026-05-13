import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// Local AI Settings panel — tier override, benchmark history, installed models, custom GGUF import.
// Tauri commands defined in src-tauri/src/commands/local_ai.rs (stubs; wired in S15.T17).
import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge } from "../../components/tier-badge";
// --- Helpers ---
function Skeleton({ className = "" }) {
    return _jsx("div", { className: `animate-pulse rounded bg-white/5 ${className}` });
}
function Toast({ message, onClose }) {
    useEffect(() => {
        const t = setTimeout(onClose, 4000);
        return () => clearTimeout(t);
    }, [onClose]);
    return (_jsx("div", { className: "fixed bottom-4 right-4 z-50 rounded-lg bg-red-900/80 px-4 py-2 text-sm text-red-200 shadow-lg", children: message }));
}
function ConfirmModal({ title, body, confirmLabel, onConfirm, onCancel, }) {
    return (_jsx("div", { className: "fixed inset-0 z-40 flex items-center justify-center bg-black/60", children: _jsxs("div", { className: "w-80 rounded-xl border border-white/10 bg-gray-900 p-6 shadow-2xl", children: [_jsx("h3", { className: "mb-2 text-base font-semibold text-white", children: title }), _jsx("p", { className: "mb-5 text-sm text-gray-400", children: body }), _jsxs("div", { className: "flex justify-end gap-3", children: [_jsx("button", { onClick: onCancel, className: "rounded-lg px-4 py-1.5 text-sm text-gray-400 hover:text-white", children: "Cancel" }), _jsx("button", { onClick: onConfirm, className: "rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-sky-500", children: confirmLabel })] })] }) }));
}
// Minimal sparkline — renders tok/s values as an inline SVG bar chart.
function Sparkline({ values }) {
    if (values.length === 0)
        return null;
    const max = Math.max(...values, 1);
    const w = 220;
    const h = 40;
    const bw = Math.floor(w / values.length) - 2;
    return (_jsx("svg", { width: w, height: h, className: "mt-1", children: values.map((v, i) => {
            const barH = Math.max(2, Math.round((v / max) * h));
            return (_jsx("rect", { x: i * (bw + 2), y: h - barH, width: bw, height: barH, rx: 2, className: "fill-sky-500/70" }, i));
        }) }));
}
// --- Main component ---
export default function LocalAiSettingsPage() {
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [tier, setTier] = useState({ active: 2, override: "auto" });
    const [benchmarks, setBenchmarks] = useState([]);
    const [models, setModels] = useState([]);
    const [allowT4, setAllowT4] = useState(false);
    const [reBenchMonthly, setReBenchMonthly] = useState(true);
    const [benchRunning, setBenchRunning] = useState(false);
    const [importRunning, setImportRunning] = useState(false);
    // Modals
    const [confirmT4, setConfirmT4] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState(null);
    const load = useCallback(async () => {
        try {
            setLoading(true);
            setError(null);
            const [t, b, m] = await Promise.all([
                invoke("get_tier"),
                invoke("get_benchmark_history", { limit: 12 }),
                invoke("list_models"),
            ]);
            setTier(t);
            setBenchmarks(b);
            setModels(m);
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setLoading(false);
        }
    }, []);
    useEffect(() => {
        load();
    }, [load]);
    const handleTierOverride = useCallback(async (value) => {
        try {
            const override = value === "auto" ? null : parseInt(value.slice(1));
            await invoke("set_tier_override", { tier: override });
            await load();
        }
        catch (e) {
            setError(String(e));
        }
    }, [load]);
    const handleAllowT4Toggle = useCallback(async (checked) => {
        if (checked) {
            setConfirmT4(true);
        }
        else {
            try {
                await invoke("set_allow_t4", { allow: false });
                setAllowT4(false);
            }
            catch (e) {
                setError(String(e));
            }
        }
    }, []);
    const confirmEnableT4 = useCallback(async () => {
        try {
            await invoke("set_allow_t4", { allow: true });
            setAllowT4(true);
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setConfirmT4(false);
        }
    }, []);
    const handleReBenchToggle = useCallback(async (checked) => {
        try {
            await invoke("set_re_bench_monthly", { enabled: checked });
            setReBenchMonthly(checked);
        }
        catch (e) {
            setError(String(e));
        }
    }, []);
    const runBenchmark = useCallback(async () => {
        try {
            setBenchRunning(true);
            await invoke("run_benchmark");
            await load();
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setBenchRunning(false);
        }
    }, [load]);
    const handleImportGGUF = useCallback(async () => {
        try {
            setImportRunning(true);
            const path = await invoke("import_custom_gguf", { path: "" });
            if (path)
                await load();
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setImportRunning(false);
        }
    }, [load]);
    const handleDeleteModel = useCallback(async (modelId) => {
        try {
            await invoke("delete_model", { modelId });
            setModels((prev) => prev.filter((m) => m.model_id !== modelId));
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setDeleteTarget(null);
        }
    }, []);
    const handleSetChatRole = useCallback(async (modelId) => {
        try {
            await invoke("set_model_role", { modelId, role: "chat" });
            await load();
        }
        catch (e) {
            setError(String(e));
        }
    }, [load]);
    // --- Render: Loading ---
    if (loading) {
        return (_jsxs("div", { className: "mx-auto max-w-2xl space-y-6 p-6", children: [_jsx(Skeleton, { className: "h-8 w-48" }), _jsx(Skeleton, { className: "h-24 w-full" }), _jsx(Skeleton, { className: "h-20 w-full" }), _jsx(Skeleton, { className: "h-32 w-full" })] }));
    }
    const sparklValues = benchmarks.map((b) => b.toks_per_sec);
    const latestBench = benchmarks[0];
    return (_jsxs(_Fragment, { children: [error && _jsx(Toast, { message: error, onClose: () => setError(null) }), confirmT4 && (_jsx(ConfirmModal, { title: "Enable T4 (Heavy) models?", body: "T4 models require 16 GB+ RAM and will fully occupy your GPU during inference. Battery drain will be significant on laptops.", confirmLabel: "Enable T4", onConfirm: confirmEnableT4, onCancel: () => setConfirmT4(false) })), deleteTarget && (_jsx(ConfirmModal, { title: "Delete model?", body: `Remove "${deleteTarget}" from disk? This cannot be undone.`, confirmLabel: "Delete", onConfirm: () => handleDeleteModel(deleteTarget), onCancel: () => setDeleteTarget(null) })), _jsxs("div", { className: "mx-auto max-w-2xl space-y-8 p-6", children: [_jsxs("div", { className: "flex items-center gap-3", children: [_jsx("h1", { className: "text-xl font-semibold text-white", children: "Local AI" }), _jsx(TierBadge, { tier: tier.active, isOverride: tier.override !== "auto" })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsx("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Tier override" }), _jsxs("select", { value: tier.override, onChange: (e) => handleTierOverride(e.target.value), className: "w-full rounded-lg border border-white/10 bg-gray-900 px-3 py-2 text-sm text-white focus:border-sky-500 focus:outline-none", children: [_jsx("option", { value: "auto", children: "Auto (recommended)" }), _jsx("option", { value: "T0", children: "T0 \u2014 Nano (<1 GB)" }), _jsx("option", { value: "T1", children: "T1 \u2014 Small (1-4 GB)" }), _jsx("option", { value: "T2", children: "T2 \u2014 Medium (4-8 GB)" }), _jsx("option", { value: "T3", children: "T3 \u2014 Large (8-16 GB)" }), _jsx("option", { value: "T4", children: "T4 \u2014 Heavy (16 GB+)" })] })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5 space-y-4", children: [_jsx(Toggle, { label: "Allow T4 (heavy models)", description: "Requires 16 GB+ RAM. Confirmation required on first enable.", checked: allowT4, onChange: handleAllowT4Toggle }), _jsx("div", { className: "border-t border-white/5" }), _jsx(Toggle, { label: "Re-benchmark monthly", description: "Automatically re-run the hardware benchmark every 30 days.", checked: reBenchMonthly, onChange: handleReBenchToggle })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsxs("div", { className: "mb-3 flex items-center justify-between", children: [_jsx("h2", { className: "text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Benchmark history" }), latestBench && (_jsxs("span", { className: "text-xs text-gray-500", children: ["Last: ", latestBench.toks_per_sec, " tok/s \u00B7 ", latestBench.date] }))] }), benchmarks.length === 0 ? (_jsx("p", { className: "text-sm text-gray-500", children: "No benchmarks yet. Run one below." })) : (_jsx(Sparkline, { values: sparklValues })), _jsx("button", { onClick: runBenchmark, disabled: benchRunning, className: "mt-4 rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50", children: benchRunning ? "Running..." : "Run benchmark again" })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsx("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Installed models" }), models.length === 0 ? (_jsx("p", { className: "text-sm text-gray-500", children: "No models installed. Add a custom GGUF below." })) : (_jsx("ul", { className: "space-y-3", children: models.map((m) => (_jsxs("li", { className: "flex items-start justify-between gap-4 rounded-lg bg-gray-900/50 px-4 py-3", children: [_jsxs("div", { className: "min-w-0 flex-1", children: [_jsx("p", { className: "truncate text-sm font-medium text-white", children: m.model_id }), _jsxs("p", { className: "mt-0.5 text-xs text-gray-500", children: [(m.size_mb / 1024).toFixed(1), " GB", m.last_used_at ? ` · last used ${m.last_used_at}` : ""] }), _jsx("div", { className: "mt-1.5 flex flex-wrap gap-1", children: m.roles.map((r) => (_jsx("span", { className: "rounded-full bg-sky-500/15 px-2 py-0.5 text-xs text-sky-400", children: r }, r))) })] }), _jsxs("div", { className: "flex shrink-0 flex-col gap-1.5 pt-0.5", children: [_jsx("button", { onClick: () => handleSetChatRole(m.model_id), className: "rounded px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10", children: "Set as chat role" }), _jsx("button", { onClick: () => setDeleteTarget(m.model_id), className: "rounded px-2 py-1 text-xs text-red-400 hover:bg-red-500/10", children: "Delete" })] })] }, m.model_id))) }))] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsx("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Add custom GGUF" }), _jsx("p", { className: "mb-3 text-sm text-gray-500", children: "Import a .gguf model file from disk. It will be registered and available for role assignment." }), _jsx("button", { onClick: handleImportGGUF, disabled: importRunning, className: "rounded-lg border border-white/10 bg-gray-900 px-4 py-1.5 text-sm text-white hover:border-sky-500/50 disabled:opacity-50", children: importRunning ? "Importing..." : "Choose file..." })] })] })] }));
}
function Toggle({ label, description, checked, onChange }) {
    return (_jsxs("div", { className: "flex items-center justify-between gap-4", children: [_jsxs("div", { children: [_jsx("p", { className: "text-sm font-medium text-white", children: label }), _jsx("p", { className: "text-xs text-gray-500", children: description })] }), _jsx("button", { role: "switch", "aria-checked": checked, onClick: () => onChange(!checked), className: `relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus:outline-none ${checked ? "bg-sky-500" : "bg-gray-700"}`, children: _jsx("span", { className: `inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${checked ? "translate-x-4" : "translate-x-0"}` }) })] }));
}
