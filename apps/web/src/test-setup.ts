/**
 * Vitest global setup for claw-web.
 *
 * Purpose: Register @testing-library/jest-dom matchers (toBeInTheDocument, etc.)
 *          on Vitest's expect, and provide their type augmentation so component
 *          tests type-check under `tsc --noEmit`.
 * Constraints: Loaded via vitest.config.ts `setupFiles`; imported here so the
 *              module augmentation of 'vitest' is part of the TS program.
 */

import '@testing-library/jest-dom/vitest';
