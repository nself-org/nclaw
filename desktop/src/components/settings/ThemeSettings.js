import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import { useNselfTranslation } from '@nself/i18n';
import { useTheme } from '@/hooks/useTheme';
import { ACCENT_PRESETS, isValidHex } from '@/lib/theme';
export function ThemeSettings() {
    const { t } = useNselfTranslation();
    const { mode, setMode, accentHex, setAccentHex } = useTheme();
    const [customHex, setCustomHex] = useState('');
    const [customError, setCustomError] = useState('');
    const handleCustomHexChange = (e) => {
        const val = e.target.value;
        setCustomHex(val);
        if (val && !isValidHex(val)) {
            setCustomError(t('desktop.nclaw.invalidHex'));
        }
        else {
            setCustomError('');
        }
    };
    const handleApplyCustom = () => {
        if (!customHex || !isValidHex(customHex)) {
            setCustomError(t('desktop.nclaw.invalidHex'));
            return;
        }
        setAccentHex(customHex.startsWith('#') ? customHex : `#${customHex}`);
        setCustomHex('');
        setCustomError('');
    };
    const handleReset = () => {
        setMode('system');
        setAccentHex('#0ea5e9');
        setCustomHex('');
        setCustomError('');
    };
    return (_jsxs("div", { className: "flex flex-col gap-6 p-6", children: [_jsxs("div", { children: [_jsx("h3", { className: "text-sm font-semibold text-slate-100 mb-3", children: t('desktop.nclaw.themeSection') }), _jsx("div", { className: "space-y-2", children: ['light', 'dark', 'system'].map((m) => (_jsxs("label", { className: "flex items-center gap-3 cursor-pointer group", children: [_jsx("input", { type: "radio", name: "theme-mode", value: m, checked: mode === m, onChange: (e) => setMode(e.target.value), className: "w-4 h-4 rounded-full border border-slate-600 bg-surface checked:bg-sky-500 checked:border-sky-400 cursor-pointer" }), _jsx("span", { className: "text-sm text-slate-300 capitalize group-hover:text-slate-100 transition-colors", children: m === 'system' ? t('desktop.nclaw.themeSystem') : m.charAt(0).toUpperCase() + m.slice(1) })] }, m))) })] }), _jsxs("div", { children: [_jsx("h3", { className: "text-sm font-semibold text-slate-100 mb-3", children: t('desktop.nclaw.accentSection') }), _jsx("div", { className: "grid grid-cols-3 gap-2", children: ACCENT_PRESETS.map((preset) => (_jsxs("button", { onClick: () => setAccentHex(preset.hex), className: `flex items-center gap-2 px-3 py-2 rounded-md transition-colors ${accentHex.toLowerCase() === preset.hex.toLowerCase()
                                ? 'bg-slate-700 ring-2 ring-offset-1 ring-offset-surface ring-sky-400'
                                : 'bg-slate-800 hover:bg-slate-700'}`, title: preset.label, children: [_jsx("div", { className: "w-3 h-3 rounded-full border border-slate-600", style: { backgroundColor: preset.hex } }), _jsx("span", { className: "text-xs text-slate-300 capitalize", children: preset.id })] }, preset.id))) })] }), _jsxs("div", { children: [_jsx("h3", { className: "text-sm font-semibold text-slate-100 mb-3", children: "Custom Color" }), _jsxs("div", { className: "flex gap-2", children: [_jsxs("div", { className: "flex-1", children: [_jsx("input", { type: "text", value: customHex, onChange: handleCustomHexChange, placeholder: "#0ea5e9", className: "w-full px-3 py-2 rounded-md bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent" }), customError && _jsx("p", { className: "text-xs text-rose-400 mt-1", children: customError })] }), _jsx("button", { onClick: handleApplyCustom, disabled: !customHex || !isValidHex(customHex), className: "px-3 py-2 rounded-md bg-sky-500/20 text-sky-400 text-sm font-medium hover:bg-sky-500/30 disabled:opacity-50 disabled:cursor-not-allowed transition-colors", children: t('desktop.nclaw.customHexApply') })] })] }), _jsxs("div", { children: [_jsx("h3", { className: "text-sm font-semibold text-slate-100 mb-3", children: "Preview" }), _jsxs("div", { className: "flex gap-3 items-center", children: [_jsx("div", { className: "w-12 h-12 rounded-lg border-2 border-slate-700", style: { backgroundColor: accentHex } }), _jsxs("div", { className: "text-sm", children: [_jsx("p", { className: "text-slate-300", children: "Current accent" }), _jsx("p", { className: "text-slate-500 font-mono text-xs", children: accentHex })] })] })] }), _jsx("button", { onClick: handleReset, className: "w-full px-4 py-2 rounded-md bg-slate-700/50 text-slate-300 text-sm font-medium hover:bg-slate-700 transition-colors", children: t('desktop.nclaw.customHexReset') })] }));
}
