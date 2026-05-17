// ɳClaw Desktop — Keyboard shortcuts reference modal
// Displays all shortcuts grouped by section; bound to '?' global hotkey
import React, { useEffect, useState } from "react";
import { getShortcuts, ShortcutDef } from "../../lib/shortcuts-registry";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ScrollArea } from "@/components/ui/scroll-area";

interface ShortcutsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function ShortcutsModal({ isOpen, onClose }: ShortcutsModalProps): React.ReactElement {
  const [shortcuts, setShortcuts] = useState<ShortcutDef[]>([]);
  const isMac = typeof navigator !== "undefined" && navigator.platform.includes("Mac");

  useEffect(() => {
    setShortcuts(getShortcuts());
  }, [isOpen]);

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
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="max-w-2xl w-11/12 max-h-[80vh] flex flex-col gap-0 p-0 overflow-hidden">
        <DialogHeader className="px-6 py-4 border-b border-slate-700 shrink-0">
          <DialogTitle className="text-lg font-bold text-slate-100">
            ⌨️ Keyboard Shortcuts
          </DialogTitle>
        </DialogHeader>

        <ScrollArea className="flex-1 px-6 py-4">
          <div className="space-y-6">
            {sections.map((section) => (
              <div key={section}>
                <h3 className="text-sm font-semibold text-sky-400 mb-3 uppercase tracking-wide">
                  {section}
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {groupedBySection[section]?.map((shortcut) => {
                    const displayKey = isMac
                      ? shortcut.current?.mac || shortcut.default.mac
                      : shortcut.current?.other || shortcut.default.other;
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
        </ScrollArea>

        <div className="px-6 py-3 border-t border-slate-700 text-xs text-slate-400 text-center shrink-0">
          Press{" "}
          <kbd className="px-1.5 py-0.5 rounded bg-slate-800 border border-slate-600 text-slate-100 font-mono">
            Esc
          </kbd>{" "}
          to close
        </div>
      </DialogContent>
    </Dialog>
  );
}
