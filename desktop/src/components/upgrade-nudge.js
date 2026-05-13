import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useRef, useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
/**
 * UpgradeNudge — modal prompt when device handles current tier well above target.
 * Single-fire per session using useRef flag + UpgradeConfig deferral.
 *
 * Copy: "Your device handled the T<N> benchmark well above target. Want to try T<N+1>?"
 * Buttons: "Yes, upgrade", "Not now", "Don't ask again"
 *
 * T4 special case: additional opt-in confirmation (T4 is not automatic).
 */
export const UpgradeNudge = ({ currentTier, recommendedTier, onDismiss, }) => {
    const sessionShownRef = useRef(false);
    const [isVisible, setIsVisible] = useState(false);
    const [showT4Confirmation, setShowT4Confirmation] = useState(false);
    useEffect(() => {
        // Single-fire per session
        if (sessionShownRef.current)
            return;
        sessionShownRef.current = true;
        checkShouldShow();
    }, []);
    const checkShouldShow = async () => {
        try {
            const config = await invoke('get_upgrade_config');
            if (config.upgrade_prompt_disabled) {
                return;
            }
            if (config.last_upgrade_prompt_at) {
                const lastPrompt = new Date(config.last_upgrade_prompt_at);
                const now = new Date();
                const daysSince = (now.getTime() - lastPrompt.getTime()) / (1000 * 60 * 60 * 24);
                if (daysSince < 30) {
                    return;
                }
            }
            setIsVisible(true);
        }
        catch (err) {
            console.error('Failed to check upgrade config:', err);
        }
    };
    const handleUpgrade = async () => {
        if (recommendedTier === 4) {
            setShowT4Confirmation(true);
            return;
        }
        await performUpgrade();
    };
    const handleConfirmT4 = async () => {
        await performUpgrade();
    };
    const performUpgrade = async () => {
        try {
            await invoke('upgrade_to_tier', { tier: recommendedTier });
            setIsVisible(false);
            setShowT4Confirmation(false);
            onDismiss?.();
        }
        catch (err) {
            console.error('Failed to upgrade tier:', err);
        }
    };
    const handleNotNow = async () => {
        try {
            await invoke('defer_upgrade_prompt_30_days');
            setIsVisible(false);
            onDismiss?.();
        }
        catch (err) {
            console.error('Failed to defer upgrade prompt:', err);
        }
    };
    const handleDontAskAgain = async () => {
        try {
            await invoke('set_upgrade_prompt_disabled', { disabled: true });
            setIsVisible(false);
            onDismiss?.();
        }
        catch (err) {
            console.error('Failed to disable upgrade prompt:', err);
        }
    };
    if (!isVisible)
        return null;
    const tierLabel = (t) => (t >= 0 && t <= 4 ? `T${t}` : 'Unknown');
    return (_jsx("div", { className: "fixed inset-0 z-50 flex items-center justify-center bg-black/50", children: _jsx("div", { className: "bg-white rounded-lg shadow-xl max-w-md w-full mx-4 p-6 space-y-4", children: showT4Confirmation ? (_jsxs(_Fragment, { children: [_jsx("h2", { className: "text-lg font-bold text-gray-900", children: "Confirm T4 Upgrade" }), _jsx("p", { className: "text-gray-700", children: "T4 (Heavy) is opt-in only \u2014 it uses very large models that may significantly impact your device. Continue?" }), _jsxs("div", { className: "flex gap-3 justify-end", children: [_jsx("button", { onClick: () => setShowT4Confirmation(false), className: "px-4 py-2 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded font-medium", children: "Cancel" }), _jsx("button", { onClick: handleConfirmT4, className: "px-4 py-2 text-white bg-blue-600 hover:bg-blue-700 rounded font-medium", children: "Continue" })] })] })) : (_jsxs(_Fragment, { children: [_jsx("h2", { className: "text-lg font-bold text-gray-900", children: "Upgrade Available" }), _jsxs("p", { className: "text-gray-700", children: ["Your device handled the ", tierLabel(currentTier), " benchmark well above target. Want to try", ' ', tierLabel(recommendedTier), "? It uses more RAM and disk but produces better answers."] }), _jsxs("div", { className: "flex flex-col gap-2", children: [_jsx("button", { onClick: handleUpgrade, className: "w-full px-4 py-2 text-white bg-blue-600 hover:bg-blue-700 rounded font-medium", children: "Yes, upgrade" }), _jsx("button", { onClick: handleNotNow, className: "w-full px-4 py-2 text-gray-700 bg-gray-100 hover:bg-gray-200 rounded font-medium", children: "Not now" }), _jsx("button", { onClick: handleDontAskAgain, className: "w-full px-4 py-2 text-gray-600 text-sm bg-transparent hover:bg-gray-50 rounded", children: "Don't ask again" })] })] })) }) }));
};
