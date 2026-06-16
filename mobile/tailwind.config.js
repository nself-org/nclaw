/**
 * Tailwind CSS v3 configuration for nclaw/mobile with NativeWind v4.
 *
 * Purpose: Enable Tailwind utility classes in RN components via NativeWind.
 * Inputs:  File glob patterns for content scanning.
 * Outputs: Tailwind CSS config.
 * Constraints: NativeWind v4 requires 'nativewind/preset' in presets array.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,ts,jsx,tsx}',
    './components/**/*.{js,ts,jsx,tsx}',
    './lib/**/*.{js,ts,jsx,tsx}',
    './hooks/**/*.{js,ts,jsx,tsx}',
  ],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#6c63ff',
          dark: '#4a42cc',
          light: '#9b95ff',
        },
        surface: {
          DEFAULT: '#1a1a2e',
          elevated: '#16213e',
          card: '#0f3460',
        },
      },
    },
  },
  plugins: [],
};
