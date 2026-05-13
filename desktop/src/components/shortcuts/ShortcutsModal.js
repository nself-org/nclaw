import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Keyboard shortcuts reference modal
// Displays all shortcuts grouped by section; bound to '?' global hotkey
import { useEffect, useState } from "react";
import { getShortcuts } from "../../lib/shortcuts-registry";
export function ShortcutsModal({ isOpen, onClose }) {
    const [shortcuts, setShortcuts] = useState([]);
    const isMac = typeof navigator !== "undefined" && navigator.platform.includes("Mac");
    useEffect(() => {
        setShortcuts(getShortcuts());
    }, [isOpen]);
    useEffect(() => {
        if (!isOpen)
            return;
        const handleKeyDown = (e) => {
            if (e.key === "Escape") {
                e.preventDefault();
                onClose();
            }
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [isOpen, onClose]);
    if (!isOpen)
        return null;
    const groupedBySection = shortcuts.reduce((acc, shortcut) => {
        if (!acc[shortcut.section])
            acc[shortcut.section] = [];
        acc[shortcut.section].push(shortcut);
        return acc;
    }, {});
    const sections = Object.keys(groupedBySection);
    return (_jsx("div", { className: "fixed inset-0 z-50 bg-black/50 flex items-center justify-center", onClick: onClose, children: _jsxs("div", { className: "bg-surface-soft border border-slate-700 rounded-lg shadow-2xl max-w-2xl w-11/12 max-h-[80vh] overflow-auto", onClick: (e) => e.stopPropagation(), children: [_jsxs("div", { className: "sticky top-0 bg-surface-soft border-b border-slate-700 px-6 py-4 flex items-center justify-between", children: [_jsx("h2", { className: "text-lg font-bold text-slate-100", children: "\u2328\uFE0F Keyboard Shortcuts" }), _jsx("button", { onClick: onClose, className: "text-slate-400 hover:text-slate-200 text-xl leading-none", "aria-label": "Close", children: "\u2715" })] }), _jsx("div", { className: "px-6 py-4 space-y-6", children: sections.map((section) => (_jsxs("div", { children: [_jsx("h3", { className: "text-sm font-semibold text-sky-400 mb-3 uppercase tracking-wide", children: section }), _jsx("div", { className: "grid grid-cols-1 md:grid-cols-2 gap-4", children: groupedBySection[section]?.map((shortcut) => {
                                    const displayKey = isMac ? shortcut.current?.mac || shortcut.default.mac : shortcut.current?.other || shortcut.default.other;
                                    return (_jsxs("div", { className: "flex items-center justify-between", children: [_jsx("span", { className: "text-sm text-slate-300", children: shortcut.label }), _jsx("kbd", { className: "px-2.5 py-1.5 rounded bg-slate-800 border border-slate-600 text-xs text-slate-100 font-mono whitespace-nowrap ml-2", children: displayKey })] }, shortcut.id));
                                }) })] }, section))) }), _jsxs("div", { className: "sticky bottom-0 bg-surface-soft border-t border-slate-700 px-6 py-3 text-xs text-slate-400 text-center", children: ["Press ", _jsx("kbd", { className: "px-1.5 py-0.5 rounded bg-slate-800 border border-slate-600 text-slate-100 font-mono", children: "Esc" }), " to close"] })] }) }));
}
