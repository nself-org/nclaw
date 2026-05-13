import React, { useState } from 'react';
import { useTheme } from '@/hooks/useTheme';
import { ACCENT_PRESETS, isValidHex } from '@/lib/theme';

export function ThemeSettings(): React.ReactElement {
  const { mode, setMode, accentHex, setAccentHex } = useTheme();
  const [customHex, setCustomHex] = useState('');
  const [customError, setCustomError] = useState('');

  const handleCustomHexChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    setCustomHex(val);
    if (val && !isValidHex(val)) {
      setCustomError('Invalid hex. Use #RRGGBB or #RRGGBBAA.');
    } else {
      setCustomError('');
    }
  };

  const handleApplyCustom = () => {
    if (!customHex || !isValidHex(customHex)) {
      setCustomError('Invalid hex. Use #RRGGBB or #RRGGBBAA.');
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

  return (
    <div className="flex flex-col gap-6 p-6">
      {/* Theme Mode Selection */}
      <div>
        <h3 className="text-sm font-semibold text-slate-100 mb-3">Theme</h3>
        <div className="space-y-2">
          {['light', 'dark', 'system'].map((m) => (
            <label key={m} className="flex items-center gap-3 cursor-pointer group">
              <input
                type="radio"
                name="theme-mode"
                value={m}
                checked={mode === m}
                onChange={(e) => setMode(e.target.value as 'light' | 'dark' | 'system')}
                className="w-4 h-4 rounded-full border border-slate-600 bg-surface checked:bg-sky-500 checked:border-sky-400 cursor-pointer"
              />
              <span className="text-sm text-slate-300 capitalize group-hover:text-slate-100 transition-colors">
                {m === 'system' ? 'System' : m.charAt(0).toUpperCase() + m.slice(1)}
              </span>
            </label>
          ))}
        </div>
      </div>

      {/* Accent Presets Grid */}
      <div>
        <h3 className="text-sm font-semibold text-slate-100 mb-3">Accent Color</h3>
        <div className="grid grid-cols-3 gap-2">
          {ACCENT_PRESETS.map((preset) => (
            <button
              key={preset.id}
              onClick={() => setAccentHex(preset.hex)}
              className={`flex items-center gap-2 px-3 py-2 rounded-md transition-colors ${
                accentHex.toLowerCase() === preset.hex.toLowerCase()
                  ? 'bg-slate-700 ring-2 ring-offset-1 ring-offset-surface ring-sky-400'
                  : 'bg-slate-800 hover:bg-slate-700'
              }`}
              title={preset.label}
            >
              <div
                className="w-3 h-3 rounded-full border border-slate-600"
                style={{ backgroundColor: preset.hex }}
              />
              <span className="text-xs text-slate-300 capitalize">{preset.id}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Custom Hex Input */}
      <div>
        <h3 className="text-sm font-semibold text-slate-100 mb-3">Custom Color</h3>
        <div className="flex gap-2">
          <div className="flex-1">
            <input
              type="text"
              value={customHex}
              onChange={handleCustomHexChange}
              placeholder="#0ea5e9"
              className="w-full px-3 py-2 rounded-md bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent"
            />
            {customError && <p className="text-xs text-rose-400 mt-1">{customError}</p>}
          </div>
          <button
            onClick={handleApplyCustom}
            disabled={!customHex || !isValidHex(customHex)}
            className="px-3 py-2 rounded-md bg-sky-500/20 text-sky-400 text-sm font-medium hover:bg-sky-500/30 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Apply
          </button>
        </div>
      </div>

      {/* Live Preview Swatch */}
      <div>
        <h3 className="text-sm font-semibold text-slate-100 mb-3">Preview</h3>
        <div className="flex gap-3 items-center">
          <div
            className="w-12 h-12 rounded-lg border-2 border-slate-700"
            style={{ backgroundColor: accentHex }}
          />
          <div className="text-sm">
            <p className="text-slate-300">Current accent</p>
            <p className="text-slate-500 font-mono text-xs">{accentHex}</p>
          </div>
        </div>
      </div>

      {/* Reset Button */}
      <button
        onClick={handleReset}
        className="w-full px-4 py-2 rounded-md bg-slate-700/50 text-slate-300 text-sm font-medium hover:bg-slate-700 transition-colors"
      >
        Reset to Defaults
      </button>
    </div>
  );
}
