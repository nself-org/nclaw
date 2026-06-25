// TierBadge — displays local AI tier (T0..T4) with sky-500 accent and override indicator.
import React from "react";

/** Numeric hardware tier level as classified by `libnclaw::tier`. T0 = Nano, T4 = Heavy. */
export type TierLevel = 0 | 1 | 2 | 3 | 4;

interface TierBadgeProps {
  tier: TierLevel;
  isOverride?: boolean;
  className?: string;
}

const TIER_LABELS: Record<TierLevel, string> = {
  0: "T0 · Nano",
  1: "T1 · Small",
  2: "T2 · Medium",
  3: "T3 · Large",
  4: "T4 · Heavy",
};

/** Inline pill badge showing the active hardware tier and whether it was user-overridden. */
export function TierBadge({ tier, isOverride = false, className = "" }: TierBadgeProps): React.ReactElement {
  const label = TIER_LABELS[tier] ?? `T${tier}`;
  const mode = isOverride ? "Override" : "Auto";

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border border-sky-500/40 bg-sky-500/10 px-3 py-0.5 text-xs font-semibold text-sky-400 ${className}`}
    >
      {label}
      <span className="text-sky-500/60">·</span>
      <span className="text-sky-300/70">{mode}</span>
    </span>
  );
}
