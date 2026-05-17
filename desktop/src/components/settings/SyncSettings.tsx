// ɳClaw Desktop — Sync Settings section
import React, { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSettings, maskKey } from "../../lib/settings-store";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";

type TestState = "idle" | "testing" | "ok" | "fail";

export function SyncSettings(): React.ReactElement {
  const { settings, saveSection } = useSettings();
  const current = settings.sync;

  const [draft, setDraft] = useState({
    server_url: current.server_url,
    license_key_raw: "",
  });
  const [saved, setSaved] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [testState, setTestState] = useState<TestState>("idle");
  const [testMessage, setTestMessage] = useState<string>("");

  useEffect(() => {
    setDraft((d) => ({ ...d, server_url: current.server_url }));
  }, [current.server_url]);

  const handleSave = async () => {
    setSaveError(null);
    try {
      const license_key_masked = draft.license_key_raw
        ? maskKey(draft.license_key_raw)
        : current.license_key_masked;
      await saveSection("sync", {
        server_url: draft.server_url,
        license_key_masked,
      });
      setDraft((d) => ({ ...d, license_key_raw: "" }));
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setSaveError(String(e));
    }
  };

  const handleTestConnection = async () => {
    setTestState("testing");
    setTestMessage("");
    try {
      const ok = await invoke<boolean>("test_sync_connection", {
        url: draft.server_url,
        key: draft.license_key_raw || "",
      });
      setTestState(ok ? "ok" : "fail");
      setTestMessage(ok ? "Connection successful." : "Connection failed. Check URL and key.");
    } catch (e) {
      setTestState("fail");
      setTestMessage(String(e));
    }
  };

  return (
    <section aria-labelledby="sync-heading">
      <h2 id="sync-heading" className="text-lg font-semibold text-slate-100 mb-4">
        Sync &amp; License
      </h2>

      {/* Server URL */}
      <div className="mb-4">
        <Label htmlFor="sync-server-url" className="block text-sm font-medium text-slate-300 mb-1">
          nSelf server URL
        </Label>
        <Input
          id="sync-server-url"
          type="url"
          value={draft.server_url}
          onChange={(e) => setDraft((d) => ({ ...d, server_url: e.target.value }))}
          placeholder="https://your-nself-server.example.com"
          aria-label="nSelf server URL"
        />
      </div>

      {/* License key */}
      <div className="mb-4">
        <Label htmlFor="sync-license-key" className="block text-sm font-medium text-slate-300 mb-1">
          License key
        </Label>
        <Input
          id="sync-license-key"
          type="password"
          value={draft.license_key_raw}
          onChange={(e) => setDraft((d) => ({ ...d, license_key_raw: e.target.value }))}
          placeholder={current.license_key_masked || "nself_pro_…"}
          autoComplete="off"
          aria-label="License key (masked)"
        />
        {current.license_key_masked && !draft.license_key_raw && (
          <p className="mt-1 text-xs text-slate-500">
            Saved key: <span className="font-mono">{current.license_key_masked}</span>
          </p>
        )}
      </div>

      {/* Test connection */}
      <div className="flex items-center gap-3 mb-4">
        <Button
          variant="secondary"
          onClick={handleTestConnection}
          disabled={!draft.server_url || testState === "testing"}
          aria-label="Test sync connection"
        >
          {testState === "testing" ? "Testing…" : "Test connection"}
        </Button>
        {testState !== "idle" && testState !== "testing" && (
          <span
            role="status"
            className={`text-sm ${testState === "ok" ? "text-green-400" : "text-red-400"}`}
          >
            {testMessage}
          </span>
        )}
      </div>

      {saveError && (
        <p role="alert" className="mb-3 text-sm text-red-400">
          {saveError}
        </p>
      )}

      <Button
        onClick={handleSave}
        aria-label="Save sync settings"
      >
        {saved ? "Saved" : "Save"}
      </Button>
    </section>
  );
}
