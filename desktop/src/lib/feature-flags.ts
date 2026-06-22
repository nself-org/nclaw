const flags = {
  memoryGraph: import.meta.env.DEV ? true : false,
};

/** Returns true when the named feature flag is enabled for the current build environment. */
export function isFeatureEnabled(name: keyof typeof flags): boolean {
  return flags[name];
}

/** Read-only view of all feature flags, for use in feature-flag-aware component logic. */
export const featureFlags = flags;
