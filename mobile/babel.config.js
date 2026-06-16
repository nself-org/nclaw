/**
 * Babel configuration for nclaw/mobile (Expo + NativeWind v4).
 *
 * Purpose: Transform TS/TSX with Expo preset; enable NativeWind v4 class-to-style
 *          transform; enable react-native-nitro-modules JSI bridge.
 * Inputs:  Babel api object.
 * Outputs: Babel config object.
 * Constraints: NativeWind v4 requires 'nativewind/babel' AFTER expo preset.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */
module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    plugins: ['nativewind/babel'],
  };
};
