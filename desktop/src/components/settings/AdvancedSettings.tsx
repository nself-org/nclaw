// ɳClaw Desktop — Advanced Settings section
import React, { useEffect, useState } from "react";
import { useSettings } from "../../lib/settings-store";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const LOG_LEVELS = ["error", "warn", "info", "debug", "trace"] as const;

interface SwitchRowProps {
  id: string;
  label: string;
  description: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}

function SwitchRow({ id, label, description, checked, onChange }: SwitchRowProps): React.ReactElement {
  return (
    <div className="flex items-start justify-between gap-4">
      <div>
        <Label htmlFor={id} className="text-sm font-medium text-slate-200 cursor-pointer">
          {label}
        </Label>
        <p className="text-xs text-slate-500 mt-0.5">{description}</p>
      </div>
      <Switch
        id={id}
        checked={checked}
        onCheckedChange={onChange}
        aria-label={label}
      />
    </div>
  );
}

export function AdvancedSettings(): React.ReactElement {
  const { settings, saveSection } = useSettings();
  const current = settings.advanced;

  const [draft, setDraft] = useState(current);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDraft(current);
  }, [current]);

  const handleSave = async () => {
    setError(null);
    try {
      await saveSection("advanced", draft);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <section aria-labelledby="advanced-heading">
      <h2 id="advanced-heading" className="text-lg font-semibold text-slate-100 mb-4">
        Advanced
      </h2>

      {/* Log level */}
      <div className="mb-5">
        <Label htmlFor="log-level" className="block text-sm font-medium text-slate-300 mb-1">
          Log level
        </Label>
        <p className="text-xs text-slate-500 mb-2">
          Controls verbosity of the local log file. Restart required for changes to take effect.
        </p>
        <Select
          value={draft.log_level}
          onValueChange={(v) =>
            setDraft((d) => ({
              ...d,
              log_level: v as typeof draft.log_level,
            }))
          }
        >
          <SelectTrigger id="log-level" aria-label="Log level">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {LOG_LEVELS.map((l) => (
              <SelectItem key={l} value={l}>
                {l.charAt(0).toUpperCase() + l.slice(1)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-4 mb-6">
        <SwitchRow
          id="toggle-telemetry"
          label="Usage telemetry"
          description="Send anonymous crash reports and usage statistics to help improve ɳClaw."
          checked={draft.telemetry}
          onChange={(v) => setDraft((d) => ({ ...d, telemetry: v }))}
        />

        <SwitchRow
          id="toggle-check-updates"
          label="Check for updates"
          description="Automatically check for new ɳClaw Desktop releases on startup."
          checked={draft.check_updates}
          onChange={(v) => setDraft((d) => ({ ...d, check_updates: v }))}
        />
      </div>

      {error && (
        <p role="alert" className="mb-3 text-sm text-red-400">
          {error}
        </p>
      )}

      <Button
        onClick={handleSave}
        aria-label="Save advanced settings"
      >
        {saved ? "Saved" : "Save"}
      </Button>
    </section>
  );
}
