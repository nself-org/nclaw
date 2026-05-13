// ɳClaw Desktop — Settings page
// Top-level window for Settings. Routes between 5 sections via a left nav.
import React, { useEffect, useState } from "react";
import { useSettings } from "../lib/settings-store";
import { ProviderSettings } from "../components/settings/ProviderSettings";
import { ModelSettings } from "../components/settings/ModelSettings";
import { VaultSettings } from "../components/settings/VaultSettings";
import { SyncSettings } from "../components/settings/SyncSettings";
import { AdvancedSettings } from "../components/settings/AdvancedSettings";

type SectionId = "provider" | "model" | "vault" | "sync" | "advanced";

interface NavItem {
  id: SectionId;
  label: string;
  icon: string; // SVG path d=""
}

const NAV_ITEMS: NavItem[] = [
  {
    id: "provider",
    label: "Provider",
    icon: "M12 3v1m0 16v1M4.22 4.22l.71.71m12.73 12.73.71.71M3 12H2m20 0h-1M4.93 19.07l.71-.71M18.36 5.64l.71-.71M12 7a5 5 0 1 0 0 10A5 5 0 0 0 12 7z",
  },
  {
    id: "model",
    label: "Model",
    icon: "M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.3 24.3 0 0 1 4.5 0m0 0v5.714a2.25 2.25 0 0 0 .659 1.591L19.5 14.5M14.25 3.104c.251.023.501.05.75.082M19.5 14.5l-1.5 7.5H6l-1.5-7.5m15 0h-15",
  },
  {
    id: "vault",
    label: "Vault",
    icon: "M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z",
  },
  {
    id: "sync",
    label: "Sync",
    icon: "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99",
  },
  {
    id: "advanced",
    label: "Advanced",
    icon: "M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z",
  },
];

const SECTION_COMPONENTS: Record<SectionId, React.ComponentType> = {
  provider: ProviderSettings,
  model: ModelSettings,
  vault: VaultSettings,
  sync: SyncSettings,
  advanced: AdvancedSettings,
};

export function Settings(): React.ReactElement {
  const [active, setActive] = useState<SectionId>("provider");
  const { load } = useSettings();

  // Load settings on mount
  useEffect(() => {
    void load();
  }, [load]);

  const ActiveSection = SECTION_COMPONENTS[active];

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-surface text-slate-100 select-none">
      {/* Left nav */}
      <nav
        aria-label="Settings sections"
        className="flex w-44 flex-col bg-surface-soft border-r border-slate-800 py-4 flex-shrink-0"
      >
        <p className="px-4 text-xs font-semibold uppercase tracking-wider text-slate-500 mb-2">
          Settings
        </p>
        <ul role="list" className="flex flex-col gap-0.5 px-2">
          {NAV_ITEMS.map((item) => {
            const isActive = active === item.id;
            return (
              <li key={item.id}>
                <button
                  onClick={() => setActive(item.id)}
                  aria-current={isActive ? "page" : undefined}
                  className={`flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-sky-500 ${
                    isActive
                      ? "bg-sky-500/15 text-sky-400"
                      : "text-slate-400 hover:bg-slate-800 hover:text-slate-200"
                  }`}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    strokeWidth={1.5}
                    stroke="currentColor"
                    className="h-4 w-4 flex-shrink-0"
                    aria-hidden="true"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" d={item.icon} />
                  </svg>
                  {item.label}
                </button>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* Content panel */}
      <main
        className="flex-1 overflow-y-auto p-8"
        aria-label={`${NAV_ITEMS.find((n) => n.id === active)?.label} settings`}
      >
        <ActiveSection />
      </main>
    </div>
  );
}

export default Settings;
