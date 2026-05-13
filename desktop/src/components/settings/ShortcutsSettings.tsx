// ɳClaw Desktop — Shortcuts settings (Advanced tab)
// Allows users to customize keyboard shortcuts with key capture
import React, { useState } from "react";
import { getShortcuts, setShortcut, resetShortcut, resetShortcuts, ShortcutDef } from "../../lib/shortcuts-registry";

export function ShortcutsSettings(): React.ReactElement {
  const [shortcuts, setShortcuts] = useState<ShortcutDef[]>(getShortcuts());
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingPlatform, setEditingPlatform] = useState<"mac" | "other" | null>(null);
  const [capturedKey, setCapturedKey] = useState<string>("");
  const isMac = typeof navigator !== "undefined" && navigator.platform.includes("Mac");

  const handleCapture = (e: React.KeyboardEvent) => {
    e.preventDefault();
    const parts: string[] = [];
    if (e.ctrlKey && !isMac) parts.push("Ctrl");
    if (e.metaKey && isMac) parts.push("⌘");
    if (e.shiftKey) parts.push("Shift");
    if (e.altKey) parts.push(isMac ? "⌥" : "Alt");
    if (e.key && !["Control", "Shift", "Alt", "Meta"].includes(e.key)) {
      parts.push(e.key === " " ? "Space" : e.key.length === 1 ? e.key.toUpperCase() : e.key);
    }
    setCapturedKey(parts.join("+") || "?");
  };

  const handleSaveShortcut = (id: string, platform: "mac" | "other") => {
    if (!capturedKey) return;
    const current = shortcuts.find((s) => s.id === id);
    if (!current) return;
    const newValue = { ...current[platform === "mac" ? "default" : "default"], [platform]: capturedKey };
    setShortcut(id, { mac: newValue.mac, other: newValue.other });
    setShortcuts(getShortcuts());
    setEditingId(null);
    setEditingPlatform(null);
    setCapturedKey("");
  };

  const handleResetOne = (id: string) => {
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

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h4 className="font-semibold text-slate-100">Keyboard Shortcuts</h4>
          <p className="text-xs text-slate-400 mt-1">Customize shortcuts per platform</p>
        </div>
        <button
          onClick={handleResetAll}
          className="px-3 py-1.5 rounded text-xs font-medium bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors"
        >
          Reset All
        </button>
      </div>

      <div className="space-y-3 max-h-96 overflow-y-auto">
        {shortcuts.map((shortcut) => {
          const macValue = shortcut.current?.mac || shortcut.default.mac;
          const otherValue = shortcut.current?.other || shortcut.default.other;
          const isEditing = editingId === shortcut.id;

          return (
            <div key={shortcut.id} className="border border-slate-700 rounded p-3 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-slate-100">{shortcut.label}</span>
                <span className="text-xs text-slate-500">{shortcut.section}</span>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {/* Mac */}
                <div>
                  <label className="text-xs text-slate-400 block mb-1">Mac</label>
                  {isEditing && editingPlatform === "mac" ? (
                    <div className="space-y-1">
                      <input
                        type="text"
                        readOnly
                        onKeyDown={handleCapture}
                        autoFocus
                        placeholder="Press keys..."
                        value={capturedKey}
                        className="w-full px-2 py-1 rounded text-xs bg-slate-800 border border-sky-500 text-slate-100 placeholder-slate-500"
                      />
                      <div className="flex gap-1">
                        <button
                          onClick={() => handleSaveShortcut(shortcut.id, "mac")}
                          className="flex-1 px-2 py-1 rounded text-xs bg-sky-600 hover:bg-sky-500 text-white transition-colors"
                        >
                          Save
                        </button>
                        <button
                          onClick={() => {
                            setEditingId(null);
                            setEditingPlatform(null);
                            setCapturedKey("");
                          }}
                          className="flex-1 px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="flex gap-1">
                      <kbd className="flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center">
                        {macValue}
                      </kbd>
                      <button
                        onClick={() => {
                          setEditingId(shortcut.id);
                          setEditingPlatform("mac");
                          setCapturedKey("");
                        }}
                        className="px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleResetOne(shortcut.id)}
                        className="px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors"
                      >
                        Reset
                      </button>
                    </div>
                  )}
                </div>

                {/* Other (Windows/Linux) */}
                <div>
                  <label className="text-xs text-slate-400 block mb-1">Windows / Linux</label>
                  {isEditing && editingPlatform === "other" ? (
                    <div className="space-y-1">
                      <input
                        type="text"
                        readOnly
                        onKeyDown={handleCapture}
                        autoFocus
                        placeholder="Press keys..."
                        value={capturedKey}
                        className="w-full px-2 py-1 rounded text-xs bg-slate-800 border border-sky-500 text-slate-100 placeholder-slate-500"
                      />
                      <div className="flex gap-1">
                        <button
                          onClick={() => handleSaveShortcut(shortcut.id, "other")}
                          className="flex-1 px-2 py-1 rounded text-xs bg-sky-600 hover:bg-sky-500 text-white transition-colors"
                        >
                          Save
                        </button>
                        <button
                          onClick={() => {
                            setEditingId(null);
                            setEditingPlatform(null);
                            setCapturedKey("");
                          }}
                          className="flex-1 px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-100 transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="flex gap-1">
                      <kbd className="flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center">
                        {otherValue}
                      </kbd>
                      <button
                        onClick={() => {
                          setEditingId(shortcut.id);
                          setEditingPlatform("other");
                          setCapturedKey("");
                        }}
                        className="px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleResetOne(shortcut.id)}
                        className="px-2 py-1 rounded text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 transition-colors"
                      >
                        Reset
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
