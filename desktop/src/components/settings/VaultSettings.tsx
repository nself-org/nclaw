// ɳClaw Desktop — Vault Settings section
import React, { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSettings } from "../../lib/settings-store";

export function VaultSettings(): React.ReactElement {
  const { settings, load } = useSettings();
  const vault = settings.vault;

  const [confirming, setConfirming] = useState(false);
  const [repairing, setRepairing] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);

  const handleRepairClick = () => {
    if (!confirming) {
      setConfirming(true);
      return;
    }
    // User confirmed — proceed
    setConfirming(false);
    doRepair();
  };

  const doRepair = async () => {
    setRepairing(true);
    setResult(null);
    try {
      await invoke("vault_repair_device");
      await load(); // refresh vault status from backend
      setResult({ ok: true, message: "Device re-paired successfully." });
    } catch (e) {
      setResult({ ok: false, message: String(e) });
    } finally {
      setRepairing(false);
    }
  };

  return (
    <section aria-labelledby="vault-heading">
      <h2 id="vault-vault" className="text-lg font-semibold text-slate-100 mb-4">
        Vault &amp; Keychain
      </h2>

      <div className="rounded-lg bg-slate-800/50 border border-slate-700 p-4 mb-6">
        <div className="flex items-center gap-3">
          <span
            aria-hidden="true"
            className={`inline-block h-2.5 w-2.5 rounded-full flex-shrink-0 ${vault.paired ? "bg-green-400" : "bg-amber-400"}`}
          />
          <div>
            <p className="text-sm font-medium text-slate-200">
              {vault.paired
                ? `Paired on ${vault.backend || "OS Keychain"}`
                : "Not paired"}
            </p>
            <p className="text-xs text-slate-500 mt-0.5">
              {vault.paired
                ? "Encryption keys are stored securely in the OS keychain."
                : "Re-pair this device to store encryption keys in the OS keychain."}
            </p>
          </div>
        </div>
      </div>

      {/* Confirmation prompt */}
      {confirming && (
        <div
          role="alert"
          className="mb-4 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm text-amber-300"
        >
          Re-pairing will generate new device keys. Any data encrypted with the current
          key will need to be re-synced. This cannot be undone.
          <div className="flex gap-2 mt-3">
            <button
              onClick={handleRepairClick}
              className="rounded-md bg-amber-600 hover:bg-amber-500 text-white px-3 py-1.5 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-amber-500"
              aria-label="Confirm device re-pair"
            >
              Confirm re-pair
            </button>
            <button
              onClick={() => setConfirming(false)}
              className="rounded-md bg-slate-700 hover:bg-slate-600 text-slate-200 px-3 py-1.5 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-slate-500"
              aria-label="Cancel re-pair"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {result && (
        <p
          role="status"
          className={`mb-4 text-sm ${result.ok ? "text-green-400" : "text-red-400"}`}
        >
          {result.message}
        </p>
      )}

      {!confirming && (
        <button
          onClick={handleRepairClick}
          disabled={repairing}
          className="rounded-md bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-slate-200 px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500"
          aria-label="Re-pair this device with the OS keychain"
        >
          {repairing ? "Re-pairing…" : "Re-pair device"}
        </button>
      )}
    </section>
  );
}
