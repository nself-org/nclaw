/**
 * Babel configuration for nclaw/mobile (Expo + NativeWind v4).
 *
 * Purpose: Transform TS/TSX with Expo preset; enable NativeWind v4 class-to-style
 *          transform; enable react-native-nitro-modules JSI bridge.
 * Inputs:  Babel api object.
 * Outputs: Babel config object.
 * Constraints: NativeWind v4 requires 'nativewind/babel' AFTER expo preset.
 *              In jest/test env nativewind/babel is skipped — Metro-only transform.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */
module.exports = function (api) {
  // Use env-based cache so changes to NODE_ENV invalidate cache
  api.cache.using(() => process.env.NODE_ENV);
  const isTest = process.env.NODE_ENV === 'test' || process.env.JEST_WORKER_ID !== undefined;
  return {
    presets: ['babel-preset-expo'],
    // nativewind/babel is a Metro/bundler transform — not compatible with jest; skip in test env
    plugins: isTest ? [] : ['nativewind/babel'],
  };
};
