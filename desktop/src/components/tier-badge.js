import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
const TIER_LABELS = {
    0: "T0 · Nano",
    1: "T1 · Small",
    2: "T2 · Medium",
    3: "T3 · Large",
    4: "T4 · Heavy",
};
export function TierBadge({ tier, isOverride = false, className = "" }) {
    const label = TIER_LABELS[tier] ?? `T${tier}`;
    const mode = isOverride ? "Override" : "Auto";
    return (_jsxs("span", { className: `inline-flex items-center gap-1.5 rounded-full border border-sky-500/40 bg-sky-500/10 px-3 py-0.5 text-xs font-semibold text-sky-400 ${className}`, children: [label, _jsx("span", { className: "text-sky-500/60", children: "\u00B7" }), _jsx("span", { className: "text-sky-300/70", children: mode })] }));
}
