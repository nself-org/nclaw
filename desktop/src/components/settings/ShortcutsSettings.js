import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// ɳClaw Desktop — Shortcuts settings (Advanced tab)
// Allows users to customize keyboard shortcuts with key capture
import { useState } from "react";
import { getShortcuts, setShortcut, resetShortcut, resetShortcuts } from "../../lib/shortcuts-registry";
export function ShortcutsSettings() {
    const [shortcuts, setShortcuts] = useState(getShortcuts());
    const [editingId, setEditingId] = useState(null);
    const [editingPlatform, setEditingPlatform] = useState(null);
    const [capturedKey, setCapturedKey] = useState("");
    const isMac = typeof navigator !== "undefined" && navigator.platform.includes("Mac");
    const handleCapture = (e) => {
        e.preventDefault();
        const parts = [];
        if (e.ctrlKey && !isMac)
            parts.push("Ctrl");
        if (e.metaKey && isMac)
            parts.push("⌘");
        if (e.shiftKey)
            parts.push("Shift");
        if (e.altKey)
            parts.push(isMac ? "⌥" : "Alt");
        if (e.key && !["Control", "Shift", "Alt", "Meta"].includes(e.key)) {
            parts.push(e.key === " " ? "Space" : e.key.length === 1 ? e.key.toUpperCase() : e.key);
        }
        setCapturedKey(parts.join("+") || "?");
    };
    const handleSaveShortcut = (id, platform) => {
        if (!capturedKey)
            return;
        const current = shortcuts.find((s) => s.id === id);
        if (!current)
            return;
        const newValue = { ...current[platform === "mac" ? "default" : "default"], [platform]: capturedKey };
        setShortcut(id, { mac: newValue.mac, other: newValue.other });
        setShortcuts(getShortcuts());
        setEditingId(null);
        setEditingPlatform(null);
        setCapturedKey("");
    };
    const handleResetOne = (id) => {
        resetShortcut(id);
        setShortcuts(getShortcuts());
        setEditingId(null);
        setEditingPlatform(null);
        setCapturedKey("");
    };
    const handleResetAll = () => {
        if (window.confirm("Reset all shortcuts to defaults?")) {
            resetShortcuts();
            setShortcuts(getShortcuts());
            setEditingId(null);
            setEditingPlatform(null);
            setCapturedKey("");
        }
    };
    return (_jsxs("div", { className: "space-y-4", children: [_jsxs("div", { className: "flex items-center justify-between", children: [_jsxs("div", { children: [_jsx("h4", { className: "font-semibold text-slate-100", children: "Keyboard Shortcuts" }), _jsx("p", { className: "text-xs text-slate-400 mt-1", children: "Customize shortcuts per platform" })] }), _jsx("button", { onClick: handleResetAll, className: "px-3 py-1.5 rounded text-xs font-medium bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors", children: "Reset All" })] }), _jsx("div", { className: "space-y-3 max-h-96 overflow-y-auto", children: shortcuts.map((shortcut) => {
                    const macValue = shortcut.current?.mac || shortcut.default.mac;
                    const otherValue = shortcut.current?.other || shortcut.default.other;
                    const isEditing = editingId === shortcut.id;
                    return (_jsxs("div", { className: "border border-slate-700 rounded p-3 space-y-2", children: [_jsxs("div", { className: "flex items-center justify-between", children: [_jsx("span", { className: "text-sm font-medium text-slate-100", children: shortcut.label }), _jsx("span", { className: "text-xs text-slate-500", children: shortcut.section })] }), _jsxs("div", { className: "grid grid-cols-2 gap-3", children: [_jsxs("div", { children: [_jsx("label", { className: "text-xs text-slate-400 block mb-1", children: "Mac" }), isEditing && editingPlatform === "mac" ? (_jsxs("div", { className: "space-y-1", children: [_jsx("input", { type: "text", readOnly: true, onKeyDown: handleCapture, autoFocus: true, placeholder: "Press keys...", value: capturedKey, className: "w-full px-2 py-1 rounded text-xs bg-slate-800 border border-sky-500 text-slate-100 placeholder-slate-500" }), _jsxs("div", { className: "flex gap-1", children: [_jsx("button", { onClick: () => handleSaveShortcut(shortcut.id, "mac"), className: "flex-1 px-2 py-1 rounded text-xs bg-sky-600 hover:bg-sky-500 text-white transition-colors", children: "Save" }), _jsx("button", { onClick: () => {
                                                                    setEditingId(null);
                                                                    setEditingPlatform(null);
                                                                    setCapturedKey("");
                                                                }, className: "flex-1 px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors", children: "Cancel" })] })] })) : (_jsxs("div", { className: "flex gap-1", children: [_jsx("kbd", { className: "flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center", children: macValue }), _jsx("button", { onClick: () => {
                                                            setEditingId(shortcut.id);
                                                            setEditingPlatform("mac");
                                                            setCapturedKey("");
                                                        }, className: "px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors", children: "Edit" }), _jsx("button", { onClick: () => handleResetOne(shortcut.id), className: "px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors", children: "Reset" })] }))] }), _jsxs("div", { children: [_jsx("label", { className: "text-xs text-slate-400 block mb-1", children: "Windows / Linux" }), isEditing && editingPlatform === "other" ? (_jsxs("div", { className: "space-y-1", children: [_jsx("input", { type: "text", readOnly: true, onKeyDown: handleCapture, autoFocus: true, placeholder: "Press keys...", value: capturedKey, className: "w-full px-2 py-1 rounded text-xs bg-slate-800 border border-sky-500 text-slate-100 placeholder-slate-500" }), _jsxs("div", { className: "flex gap-1", children: [_jsx("button", { onClick: () => handleSaveShortcut(shortcut.id, "other"), className: "flex-1 px-2 py-1 rounded text-xs bg-sky-600 hover:bg-sky-500 text-white transition-colors", children: "Save" }), _jsx("button", { onClick: () => {
                                                                    setEditingId(null);
                                                                    setEditingPlatform(null);
                                                                    setCapturedKey("");
                                                                }, className: "flex-1 px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors", children: "Cancel" })] })] })) : (_jsxs("div", { className: "flex gap-1", children: [_jsx("kbd", { className: "flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center", children: otherValue }), _jsx("button", { onClick: () => {
                                                            setEditingId(shortcut.id);
                                                            setEditingPlatform("other");
                                                            setCapturedKey("");
                                                        }, className: "px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors", children: "Edit" }), _jsx("button", { onClick: () => handleResetOne(shortcut.id), className: "px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors", children: "Reset" })] }))] })] })] }, shortcut.id));
                }) })] }));
}
