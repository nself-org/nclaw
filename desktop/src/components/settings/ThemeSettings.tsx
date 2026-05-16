import React, { useState } from 'react';
import { useTheme } from '@/hooks/useTheme';
import { ACCENT_PRESETS, isValidHex } from '@/lib/theme';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';

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
          {(['light', 'dark', 'system'] as const).map((m) => (
            <label key={m} className="flex items-center gap-3 cursor-pointer group">
              <input
                type="radio"
                name="theme-mode"
                value={m}
                checked={mode === m}
                onChange={() => setMode(m)}
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
            <Label htmlFor="custom-hex-input" className="sr-only">
              Custom hex color
            </Label>
            <Input
              id="custom-hex-input"
              type="text"
              value={customHex}
              onChange={handleCustomHexChange}
              placeholder="#0ea5e9"
              aria-label="Custom hex color"
            />
            {customError && <p className="text-xs text-rose-400 mt-1">{customError}</p>}
          </div>
          <Button
            onClick={handleApplyCustom}
            disabled={!customHex || !isValidHex(customHex)}
            variant="secondary"
          >
            Apply
          </Button>
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
      <Button
        variant="secondary"
        onClick={handleReset}
        className="w-full"
      >
        Reset to Defaults
      </Button>
    </div>
  );
}
