// ɳClaw Desktop — Shortcuts settings (Advanced tab)
// Allows users to customize keyboard shortcuts with key capture
import React, { useState } from "react";
import { getShortcuts, setShortcut, resetShortcut, resetShortcuts, ShortcutDef } from "../../lib/shortcuts-registry";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface EditTarget {
  id: string;
  platform: "mac" | "other";
}

export function ShortcutsSettings(): React.ReactElement {
  const [shortcuts, setShortcuts] = useState<ShortcutDef[]>(getShortcuts());
  const [editTarget, setEditTarget] = useState<EditTarget | null>(null);
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

  const handleOpenEdit = (id: string, platform: "mac" | "other") => {
    setEditTarget({ id, platform });
    setCapturedKey("");
  };

  const handleSaveShortcut = () => {
    if (!editTarget || !capturedKey) return;
    const { id, platform } = editTarget;
    const current = shortcuts.find((s) => s.id === id);
    if (!current) return;
    const newValue = { ...current[platform === "mac" ? "default" : "default"], [platform]: capturedKey };
    setShortcut(id, { mac: newValue.mac, other: newValue.other });
    setShortcuts(getShortcuts());
    setEditTarget(null);
    setCapturedKey("");
  };

  const handleCancelEdit = () => {
    setEditTarget(null);
    setCapturedKey("");
  };

  const handleResetOne = (id: string) => {
    resetShortcut(id);
    setShortcuts(getShortcuts());
    setEditTarget(null);
    setCapturedKey("");
  };

  const handleResetAll = () => {
    if (window.confirm("Reset all shortcuts to defaults?")) {
      resetShortcuts();
      setShortcuts(getShortcuts());
      setEditTarget(null);
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
        <Button variant="secondary" size="sm" onClick={handleResetAll}>
          Reset All
        </Button>
      </div>

      <div className="space-y-3 max-h-96 overflow-y-auto">
        {shortcuts.map((shortcut) => {
          const macValue = shortcut.current?.mac || shortcut.default.mac;
          const otherValue = shortcut.current?.other || shortcut.default.other;

          return (
            <div key={shortcut.id} className="border border-slate-700 rounded p-3 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-slate-100">{shortcut.label}</span>
                <span className="text-xs text-slate-500">{shortcut.section}</span>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {/* Mac */}
                <div>
                  <Label className="text-xs text-slate-400 block mb-1">Mac</Label>
                  <div className="flex gap-1">
                    <kbd className="flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center">
                      {macValue}
                    </kbd>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleOpenEdit(shortcut.id, "mac")}
                      className="px-2 py-1 text-xs h-auto"
                    >
                      Edit
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleResetOne(shortcut.id)}
                      className="px-2 py-1 text-xs h-auto"
                    >
                      Reset
                    </Button>
                  </div>
                </div>

                {/* Other (Windows/Linux) */}
                <div>
                  <Label className="text-xs text-slate-400 block mb-1">Windows / Linux</Label>
                  <div className="flex gap-1">
                    <kbd className="flex-1 px-2 py-1 rounded text-xs bg-slate-800 border border-slate-600 text-slate-100 font-mono text-center">
                      {otherValue}
                    </kbd>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleOpenEdit(shortcut.id, "other")}
                      className="px-2 py-1 text-xs h-auto"
                    >
                      Edit
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleResetOne(shortcut.id)}
                      className="px-2 py-1 text-xs h-auto"
                    >
                      Reset
                    </Button>
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Key capture Dialog */}
      <Dialog open={editTarget !== null} onOpenChange={(open) => { if (!open) handleCancelEdit(); }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>
              Capture shortcut — {editTarget?.platform === "mac" ? "Mac" : "Windows / Linux"}
            </DialogTitle>
          </DialogHeader>
          <div className="py-2">
            <Label htmlFor="key-capture-input" className="text-sm text-slate-300 mb-2 block">
              Press the key combination you want to assign:
            </Label>
            <Input
              id="key-capture-input"
              type="text"
              readOnly
              onKeyDown={handleCapture}
              autoFocus
              placeholder="Press keys…"
              value={capturedKey}
              aria-label="Captured key combination"
            />
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={handleCancelEdit}>
              Cancel
            </Button>
            <Button onClick={handleSaveShortcut} disabled={!capturedKey}>
              Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
