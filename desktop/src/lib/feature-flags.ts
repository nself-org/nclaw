const flags = {
  memoryGraph: import.meta.env.DEV ? true : false,
};

export function isFeatureEnabled(name: keyof typeof flags): boolean {
  return flags[name];
}

export const featureFlags = flags;
