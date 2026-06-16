/**
 * Metro bundler configuration for nclaw/mobile.
 *
 * Purpose: Wire NativeWind v4 CSS transform, react-native-nitro-modules turboModulesPaths,
 *          and monorepo workspace package resolution.
 * Inputs:  Metro resolver + transformer hooks.
 * Outputs: Metro config object.
 * Constraints:
 *   - nitro-modules requires turboModulesPaths to find JSI codegen output.
 *   - NativeWind v4 requires withNativeWind wrapper on metro config.
 *   - Workspace packages resolved via watchFolders pointing to packages/.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */
const { getDefaultConfig } = require('expo/metro-config');
const { withNativeWind } = require('nativewind/metro');
const path = require('path');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');

const config = getDefaultConfig(projectRoot);

// --- Monorepo workspace resolution ---
config.watchFolders = [workspaceRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];

// --- react-native-nitro-modules JSI turbo modules ---
config.resolver.turboModulesPaths = [
  path.resolve(projectRoot, 'node_modules/react-native-nitro-modules'),
];

// --- NativeWind v4 CSS-in-JS ---
module.exports = withNativeWind(config, { input: './global.css' });
