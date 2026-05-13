const flags = {
    memoryGraph: import.meta.env.DEV ? true : false,
};
export function isFeatureEnabled(name) {
    return flags[name];
}
export const featureFlags = flags;
