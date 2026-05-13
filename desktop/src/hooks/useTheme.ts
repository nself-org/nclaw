import { useEffect, useState } from 'react';
import { ThemeMode, applyTheme, loadThemeFromStorage, saveTheme } from '@/lib/theme';

export function useTheme() {
  const initial = loadThemeFromStorage();
  const [mode, setMode] = useState<ThemeMode>(initial.mode);
  const [accentHex, setAccentHex] = useState(initial.accentHex);

  useEffect(() => {
    applyTheme(mode, accentHex);
    saveTheme(mode, accentHex);
  }, [mode, accentHex]);

  // React to OS theme changes when mode === 'system'
  useEffect(() => {
    if (mode !== 'system') return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => applyTheme('system', accentHex);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, [mode, accentHex]);

  return { mode, setMode, accentHex, setAccentHex };
}
