// ɳClaw Desktop — Global keyboard shortcut hook
import { useEffect } from 'react';
/**
 * Global keyboard shortcut listener.
 * @param key Shortcut key pattern (e.g. 'k', 'shift+p', 'alt+n')
 * @param handler Callback when shortcut is pressed
 */
export function useGlobalShortcut(key, handler) {
    useEffect(() => {
        const onKey = (e) => {
            const isMac = navigator.platform.includes('Mac');
            const meta = isMac ? e.metaKey : e.ctrlKey;
            // Parse key pattern: 'k' | 'shift+p' | 'alt+n'
            const parts = key.toLowerCase().split('+');
            const k = parts[parts.length - 1];
            const shift = parts.includes('shift');
            const alt = parts.includes('alt');
            // Check if key matches (case-insensitive letter matching)
            if (meta &&
                e.shiftKey === shift &&
                e.altKey === alt &&
                e.key.toLowerCase() === k) {
                e.preventDefault();
                handler();
            }
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [key, handler]);
}
