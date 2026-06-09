/**
 * Purpose: Unit tests for env-vars-check.js
 *          Runs with Node.js built-in test runner (node --test, Node 18+).
 * Inputs:  checkEnvVars() called with known-good and known-bad configs
 * Outputs: pass/fail assertions
 * Constraints: No external dependencies. Pure Node.js.
 * SPORT: F09-ENV-VAR-INVENTORY.md
 */

'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { checkEnvVars } = require('./env-vars-check');

// ---------------------------------------------------------------------------
// Known-good nclaw auth config (all AUTH_-prefixed, no stray vars)
// ---------------------------------------------------------------------------
const KNOWN_GOOD_AUTH_CONFIG = {
  NSELF_PLUGIN_LICENSE_KEY: 'nself_pro_testkey_aaabbbcccdddeeefffggghhh',
  NSELF_DOMAIN: 'localhost',
  NSELF_ENV: 'development',
  POSTGRES_PASSWORD: 'devpass',
  HASURA_GRAPHQL_ADMIN_SECRET: 'adminsecret',
  AUTH_JWT_SECRET: 'jwt_secret_at_least_32_chars_xxxxx',
  AUTH_WEBAUTHN_ENABLED: 'false',   // correct AUTH_ prefix
  AUTH_WEBAUTHN_RP_ID: 'localhost',
  AUTH_WEBAUTHN_RP_NAME: 'nSelf',
  AI_OPENAI_API_KEY: 'sk-test',
  AI_DEFAULT_PROVIDER: 'openai',
  AI_DEFAULT_MODEL: 'gpt-4o',
  MINIO_ROOT_USER: 'nself',
  MINIO_ROOT_PASSWORD: 'miniopass',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test('known-good nclaw auth config: no exception, valid=true, no errors', function () {
  const result = checkEnvVars(KNOWN_GOOD_AUTH_CONFIG);
  assert.equal(result.valid, true, 'expected valid=true for known-good config');
  assert.deepEqual(result.errors, [], 'expected no errors for known-good config');
});

test('known-good config with throwOnError: does not throw', function () {
  assert.doesNotThrow(function () {
    checkEnvVars(KNOWN_GOOD_AUTH_CONFIG, { throwOnError: true });
  });
});

test('deprecated WEBAUTHN_ENABLED (no AUTH_ prefix): warning, not error, valid=true', function () {
  // This is the field that caused the nclaw_auth crash loop on camclaw.
  // The old .env.example used WEBAUTHN_ENABLED; hasura-auth requires AUTH_WEBAUTHN_ENABLED.
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    WEBAUTHN_ENABLED: 'false',   // deprecated — no AUTH_ prefix
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, true, 'deprecated var should warn, not error');
  assert.equal(result.errors.length, 0, 'no errors expected for deprecated var');
  assert.ok(
    result.warnings.some(function (w) { return w.includes('WEBAUTHN_ENABLED'); }),
    'expected a warning mentioning WEBAUTHN_ENABLED'
  );
  assert.ok(
    result.warnings.some(function (w) { return w.includes('AUTH_WEBAUTHN_ENABLED'); }),
    'expected warning to mention the correct replacement AUTH_WEBAUTHN_ENABLED'
  );
});

test('deprecated WEBAUTHN_RP_ID and WEBAUTHN_RP_NAME: warnings, not errors', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    WEBAUTHN_RP_ID: 'example.com',
    WEBAUTHN_RP_NAME: 'MyApp',
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, true);
  assert.equal(result.errors.length, 0);
  assert.equal(result.warnings.length, 2, 'expected two deprecation warnings');
});

test('AUTH_PROVIDER_* passthrough: allowed without explicit entry', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    AUTH_PROVIDER_GITHUB_CLIENT_ID: 'ghid',
    AUTH_PROVIDER_GITHUB_CLIENT_SECRET: 'ghsecret',
    AUTH_PROVIDER_GOOGLE_ENABLED: 'true',
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, true);
  assert.deepEqual(result.errors, []);
});

test('REMOTE_SCHEMA_* passthrough: allowed', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    REMOTE_SCHEMA_PAYMENTS_URL: 'http://payments:3000/graphql',
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, true);
  assert.deepEqual(result.errors, []);
});

test('truly unknown var: error, valid=false', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    MY_CUSTOM_UNKNOWN_VAR: 'value',
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, false, 'unknown var should produce invalid result');
  assert.ok(
    result.errors.some(function (e) { return e.includes('MY_CUSTOM_UNKNOWN_VAR'); }),
    'error should mention the unknown var name'
  );
});

test('unknown var with throwOnError: throws Error', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    DEFINITELY_NOT_ALLOWED: 'boom',
  });
  assert.throws(function () {
    checkEnvVars(config, { throwOnError: true });
  }, function (err) {
    return err instanceof Error && err.message.includes('DEFINITELY_NOT_ALLOWED');
  });
});

test('empty config object: valid=true, no errors', function () {
  const result = checkEnvVars({});
  assert.equal(result.valid, true);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.warnings, []);
});

test('vars with empty string values are skipped (no false positives)', function () {
  const config = Object.assign({}, KNOWN_GOOD_AUTH_CONFIG, {
    AI_ANTHROPIC_API_KEY: '',   // allowed var, empty — should be skipped
  });
  const result = checkEnvVars(config);
  assert.equal(result.valid, true);
  assert.deepEqual(result.errors, []);
});
