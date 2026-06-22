import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
/**
 * Local AI Settings page — tier override, benchmark history, installed models, custom GGUF import.
 *
 * Tauri commands are defined in src-tauri/src/commands/local_ai.rs (stubs; wired in S15.T17).
 * Types and UI micro-components are in `./_local-ai-helpers.tsx`.
 */
import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge } from "../../components/tier-badge";
import { ConfirmModal, ModelsList, Skeleton, Sparkline, Toast, Toggle, } from "./_local-ai-helpers";
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
    if (loading) {
        return (_jsxs("div", { className: "mx-auto max-w-2xl space-y-6 p-6", children: [_jsx(Skeleton, { className: "h-8 w-48" }), _jsx(Skeleton, { className: "h-24 w-full" }), _jsx(Skeleton, { className: "h-20 w-full" }), _jsx(Skeleton, { className: "h-32 w-full" })] }));
    }
    const sparklValues = benchmarks.map((b) => b.toks_per_sec);
    const latestBench = benchmarks[0];
    return (_jsxs(_Fragment, { children: [error && _jsx(Toast, { message: error, onClose: () => setError(null) }), confirmT4 && (_jsx(ConfirmModal, { title: "Enable T4 (Heavy) models?", body: "T4 models require 16 GB+ RAM and will fully occupy your GPU during inference. Battery drain will be significant on laptops.", confirmLabel: "Enable T4", onConfirm: confirmEnableT4, onCancel: () => setConfirmT4(false) })), deleteTarget && (_jsx(ConfirmModal, { title: "Delete model?", body: `Remove "${deleteTarget}" from disk? This cannot be undone.`, confirmLabel: "Delete", onConfirm: () => handleDeleteModel(deleteTarget), onCancel: () => setDeleteTarget(null) })), _jsxs("div", { className: "mx-auto max-w-2xl space-y-8 p-6", children: [_jsxs("div", { className: "flex items-center gap-3", children: [_jsx("h1", { className: "text-xl font-semibold text-white", children: "Local AI" }), _jsx(TierBadge, { tier: tier.active, isOverride: tier.override !== "auto" })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsx("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Tier override" }), _jsxs("select", { value: tier.override, onChange: (e) => handleTierOverride(e.target.value), className: "w-full rounded-lg border border-white/10 bg-gray-900 px-3 py-2 text-sm text-white focus:border-sky-500 focus:outline-none", children: [_jsx("option", { value: "auto", children: "Auto (recommended)" }), _jsx("option", { value: "T0", children: "T0 \u2014 Nano (<1 GB)" }), _jsx("option", { value: "T1", children: "T1 \u2014 Small (1-4 GB)" }), _jsx("option", { value: "T2", children: "T2 \u2014 Medium (4-8 GB)" }), _jsx("option", { value: "T3", children: "T3 \u2014 Large (8-16 GB)" }), _jsx("option", { value: "T4", children: "T4 \u2014 Heavy (16 GB+)" })] })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5 space-y-4", children: [_jsx(Toggle, { label: "Allow T4 (heavy models)", description: "Requires 16 GB+ RAM. Confirmation required on first enable.", checked: allowT4, onChange: handleAllowT4Toggle }), _jsx("div", { className: "border-t border-white/5" }), _jsx(Toggle, { label: "Re-benchmark monthly", description: "Automatically re-run the hardware benchmark every 30 days.", checked: reBenchMonthly, onChange: handleReBenchToggle })] }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsxs("div", { className: "mb-3 flex items-center justify-between", children: [_jsx("h2", { className: "text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Benchmark history" }), latestBench && (_jsxs("span", { className: "text-xs text-gray-500", children: ["Last: ", latestBench.toks_per_sec, " tok/s \u00B7 ", latestBench.date] }))] }), benchmarks.length === 0 ? (_jsx("p", { className: "text-sm text-gray-500", children: "No benchmarks yet. Run one below." })) : (_jsx(Sparkline, { values: sparklValues })), _jsx("button", { onClick: runBenchmark, disabled: benchRunning, className: "mt-4 rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50", children: benchRunning ? "Running..." : "Run benchmark again" })] }), _jsx(ModelsList, { models: models, onSetChatRole: handleSetChatRole, onDeleteRequest: setDeleteTarget }), _jsxs("section", { className: "rounded-xl border border-white/10 bg-surface-soft p-5", children: [_jsx("h2", { className: "mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400", children: "Add custom GGUF" }), _jsx("p", { className: "mb-3 text-sm text-gray-500", children: "Import a .gguf model file from disk. It will be registered and available for role assignment." }), _jsx("button", { onClick: handleImportGGUF, disabled: importRunning, className: "rounded-lg border border-white/10 bg-gray-900 px-4 py-1.5 text-sm text-white hover:border-sky-500/50 disabled:opacity-50", children: importRunning ? "Importing..." : "Choose file..." })] })] })] }));
}
