// ɳClaw Desktop — Keyboard shortcuts reference modal
// Displays all shortcuts grouped by section; bound to '?' global hotkey
import React, { useEffect, useState } from "react";
import { getShortcuts, ShortcutDef } from "../../lib/shortcuts-registry";

interface ShortcutsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function ShortcutsModal({ isOpen, onClose }: ShortcutsModalProps): React.ReactElement | null {
  const [shortcuts, setShortcuts] = useState<ShortcutDef[]>([]);
  const isMac = typeof navigator !== "undefined" && navigator.platform.includes("Mac");

  useEffect(() => {
    setShortcuts(getShortcuts());
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const groupedBySection = shortcuts.reduce(
    (acc, shortcut) => {
      if (!acc[shortcut.section]) acc[shortcut.section] = [];
      acc[shortcut.section].push(shortcut);
      return acc;
    },
    {} as Record<string, ShortcutDef[]>
  );

  const sections = Object.keys(groupedBySection) as Array<keyof typeof groupedBySection>;

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center" onClick={onClose}>
      <div
        className="bg-surface-soft border border-slate-700 rounded-lg shadow-2xl max-w-2xl w-11/12 max-h-[80vh] overflow-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="sticky top-0 bg-surface-soft border-b border-slate-700 px-6 py-4 flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-100">⌨️ Keyboard Shortcuts</h2>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-200 text-xl leading-none"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {/* Content */}
        <div className="px-6 py-4 space-y-6">
          {sections.map((section) => (
            <div key={section}>
              <h3 className="text-sm font-semibold text-sky-400 mb-3 uppercase tracking-wide">
                {section}
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {groupedBySection[section]?.map((shortcut) => {
                  const displayKey = isMac ? shortcut.current?.mac || shortcut.default.mac : shortcut.current?.other || shortcut.default.other;
                  return (
                    <div key={shortcut.id} className="flex items-center justify-between">
                      <span className="text-sm text-slate-300">{shortcut.label}</span>
                      <kbd className="px-2.5 py-1.5 rounded bg-slate-800 border border-slate-600 text-xs text-slate-100 font-mono whitespace-nowrap ml-2">
                        {displayKey}
                      </kbd>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 bg-surface-soft border-t border-slate-700 px-6 py-3 text-xs text-slate-400 text-center">
          Press <kbd className="px-1.5 py-0.5 rounded bg-slate-800 border border-slate-600 text-slate-100 font-mono">Esc</kbd> to close
        </div>
      </div>
    </div>
  );
}
