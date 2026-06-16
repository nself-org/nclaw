/**
 * Purpose: Unit tests for feature-flags module.
 * Inputs:  featureFlags object, isFeatureEnabled helper.
 * Outputs: Vitest pass/fail assertions.
 * Constraints: No DOM, no Tauri, pure TS.
 * SPORT: T-P3-E6-W2-S6-T01
 */
import { describe, it, expect } from "vitest";
import { isFeatureEnabled, featureFlags } from "./feature-flags";

describe("isFeatureEnabled", () => {
  it("returns a boolean for every defined flag", () => {
    for (const key of Object.keys(featureFlags) as Array<keyof typeof featureFlags>) {
      expect(typeof isFeatureEnabled(key)).toBe("boolean");
    }
  });

  it("memoryGraph flag exists", () => {
    expect("memoryGraph" in featureFlags).toBe(true);
  });
});
