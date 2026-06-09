/**
 * Purpose: Pre-flight env-var validator for the nClaw backend.
 *          Runs before `nself build` to surface config problems early.
 * Inputs:  process.env OR an explicit config object passed via checkEnvVars(config)
 * Outputs: { valid: boolean, errors: string[], warnings: string[] }
 *          Throws if called with throwOnError=true and errors are found.
 * Constraints: Pure Node.js (no dependencies). Safe to require from test runner.
 * SPORT: F09-ENV-VAR-INVENTORY.md — nClaw backend env var allowlist
 *
 * WHY this file exists:
 *   The nhost/hasura-auth container (nhost/hasura-auth:0.36.0) ships its own
 *   env-vars-check.js that crashes the container on startup if it encounters
 *   any env var not in its internal allowlist (e.g. WEBAUTHN_ENABLED instead of
 *   AUTH_WEBAUTHN_ENABLED). This pre-flight script catches such misconfigurations
 *   before `nself build` so the container never sees invalid vars.
 *
 * Usage:
 *   node backend/scripts/env-vars-check.js          # validate process.env; exit 1 on error
 *   require('./env-vars-check').checkEnvVars(obj)   # validate object; returns result
 */

'use strict';

// ---------------------------------------------------------------------------
// Allowlist of every env var the nClaw backend accepts.
// Format: exact match. The AUTH_PROVIDER_* prefix is checked dynamically below.
// Any var present in the env but NOT in this list (and not a known deprecated var)
// is an error to prevent hasura-auth crash-loops.
// ---------------------------------------------------------------------------

/** @type {Set<string>} */
const ALLOWED_VARS = new Set([
  // nSelf license
  'NSELF_PLUGIN_LICENSE_KEY',

  // Core nSelf config
  'NSELF_DOMAIN',
  'NSELF_ENV',

  // Database
  'POSTGRES_PASSWORD',
  'POSTGRES_HOST',
  'POSTGRES_PORT',
  'POSTGRES_DB',
  'POSTGRES_USER',
  'DATABASE_URL',

  // Hasura
  'HASURA_GRAPHQL_ADMIN_SECRET',
  'HASURA_GRAPHQL_JWT_SECRET',
  'HASURA_GRAPHQL_DATABASE_URL',
  'HASURA_GRAPHQL_GRAPHQL_URL',

  // Auth (nhost/hasura-auth) — must use AUTH_ prefix
  'AUTH_HOST',
  'AUTH_PORT',
  'AUTH_LOG_LEVEL',
  'AUTH_WEBAUTHN_ENABLED',    // correct — hasura-auth recognises this
  'AUTH_WEBAUTHN_RP_ID',
  'AUTH_WEBAUTHN_RP_NAME',
  'AUTH_DATABASE_URL',
  'AUTH_DB_HOST',
  'AUTH_DB_PORT',
  'AUTH_DB_NAME',
  'AUTH_DB_USER',
  'AUTH_DB_PASSWORD',
  'AUTH_DB_URL',
  'AUTH_SERVER_URL',
  'AUTH_CLIENT_URL',
  'AUTH_JWT_SECRET',
  'AUTH_JWT_TYPE',
  'AUTH_ACCESS_TOKEN_EXPIRES_IN',
  'AUTH_REFRESH_TOKEN_EXPIRES_IN',
  'AUTH_ALLOWED_REDIRECT_URLS',
  'AUTH_EXTRA_REDIRECT_URLS',
  'AUTH_SMTP_HOST',
  'AUTH_SMTP_PORT',
  'AUTH_SMTP_USER',
  'AUTH_SMTP_PASS',
  'AUTH_SMTP_SECURE',
  'AUTH_SMTP_SENDER',
  'AUTH_EMAIL_SIGNIN_EMAIL_VERIFIED_REQUIRED',

  // AI provider
  'AI_OPENAI_API_KEY',
  'AI_ANTHROPIC_API_KEY',
  'AI_DEFAULT_PROVIDER',
  'AI_DEFAULT_MODEL',

  // Google integration
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',

  // Browser automation
  'BROWSER_CDP_URL',

  // SMTP / Notifications
  'SMTP_HOST',
  'SMTP_PORT',
  'SMTP_USER',
  'SMTP_PASSWORD',
  'SMTP_FROM',

  // MinIO / Storage
  'MINIO_ROOT_USER',
  'MINIO_ROOT_PASSWORD',
]);

/**
 * Deprecated env vars that were previously documented but have been superseded.
 * These are emitted as warnings (not errors) so existing deployments get migration
 * guidance without crashing.
 *
 * @type {Map<string, string>} oldName → replacement guidance
 */
const DEPRECATED_VARS = new Map([
  // The .env.example previously used WEBAUTHN_ENABLED without the AUTH_ prefix.
  // nhost/hasura-auth requires AUTH_WEBAUTHN_ENABLED.  Any deployment that set
  // WEBAUTHN_ENABLED would have their config silently ignored by the CLI (which
  // reads AUTH_WEBAUTHN_ENABLED) while the naked var was injected into the
  // container environment, causing env-vars-check.js inside the container to crash.
  ['WEBAUTHN_ENABLED',  'Use AUTH_WEBAUTHN_ENABLED instead (AUTH_ prefix required by nhost/hasura-auth)'],
  ['WEBAUTHN_RP_ID',    'Use AUTH_WEBAUTHN_RP_ID instead (AUTH_ prefix required by nhost/hasura-auth)'],
  ['WEBAUTHN_RP_NAME',  'Use AUTH_WEBAUTHN_RP_NAME instead (AUTH_ prefix required by nhost/hasura-auth)'],
]);

/**
 * Dynamic prefix rules: any var whose name starts with one of these prefixes
 * is allowed without an explicit entry in ALLOWED_VARS.
 * These map to the CLI passthrough mechanism (AUTH_PROVIDER_*, etc.).
 */
const ALLOWED_PREFIXES = [
  'AUTH_PROVIDER_',
  'REMOTE_SCHEMA_',
  'HASURA_EXTRA_',
];

// ---------------------------------------------------------------------------
// Core validator
// ---------------------------------------------------------------------------

/**
 * Check a config object (or process.env) for invalid / deprecated vars.
 *
 * @param {Record<string, string | undefined>} [config] - defaults to process.env
 * @param {{ throwOnError?: boolean }} [opts]
 * @returns {{ valid: boolean, errors: string[], warnings: string[] }}
 */
function checkEnvVars(config, opts) {
  const env = config !== undefined ? config : process.env;
  const throwOnError = (opts && opts.throwOnError) || false;

  const errors = [];
  const warnings = [];

  for (const key of Object.keys(env)) {
    // Skip empty / undefined values.
    if (env[key] === undefined || env[key] === '') continue;

    // Check deprecated vars first — warn, don't error.
    if (DEPRECATED_VARS.has(key)) {
      warnings.push(
        `DEPRECATED env var "${key}": ${DEPRECATED_VARS.get(key)}`
      );
      continue;
    }

    // Exact-match in allowlist.
    if (ALLOWED_VARS.has(key)) continue;

    // Dynamic prefix allowlist.
    if (ALLOWED_PREFIXES.some(function (p) { return key.startsWith(p); })) continue;

    // Unknown var — this is what causes the hasura-auth crash loop.
    errors.push(
      `Unknown env var "${key}". Either remove it, add it to the nClaw allowlist, ` +
      'or verify it belongs to an AUTH_PROVIDER_* / REMOTE_SCHEMA_* / HASURA_EXTRA_* group.'
    );
  }

  const valid = errors.length === 0;

  if (!valid && throwOnError) {
    throw new Error(
      'nClaw env-vars-check failed:\n' +
        errors.map(function (e) { return '  - ' + e; }).join('\n')
    );
  }

  return { valid, errors, warnings };
}

// ---------------------------------------------------------------------------
// Parse a .env file into a plain object (no shell expansion, no interpolation)
// ---------------------------------------------------------------------------

/**
 * Parse the contents of a .env file into a key-value map.
 * Lines starting with # are comments. Blank lines are skipped.
 * Values may be quoted with " or '; quotes are stripped.
 *
 * @param {string} text - file contents
 * @returns {Record<string, string>}
 */
function parseEnvFile(text) {
  var result = {};
  var lines = text.split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line || line.charAt(0) === '#') continue;
    var eqIdx = line.indexOf('=');
    if (eqIdx === -1) continue;
    var key = line.slice(0, eqIdx).trim();
    var val = line.slice(eqIdx + 1).trim();
    // Strip surrounding quotes
    if (
      (val.charAt(0) === '"' && val.charAt(val.length - 1) === '"') ||
      (val.charAt(0) === "'" && val.charAt(val.length - 1) === "'")
    ) {
      val = val.slice(1, -1);
    }
    // Skip inline comments after the value (unquoted values only)
    var commentIdx = val.indexOf(' #');
    if (commentIdx !== -1) {
      val = val.slice(0, commentIdx).trim();
    }
    if (key) result[key] = val;
  }
  return result;
}

// ---------------------------------------------------------------------------
// CLI entry-point
// ---------------------------------------------------------------------------

if (require.main === module) {
  var fs = require('fs');
  var path = require('path');

  // Accept an explicit .env path as argument, otherwise default to ../.env
  // relative to this script (i.e., backend/.env).
  var envFile = process.argv[2] || path.join(__dirname, '..', '.env');

  var config;
  if (fs.existsSync(envFile)) {
    var text = fs.readFileSync(envFile, 'utf8');
    config = parseEnvFile(text);
  } else {
    process.stderr.write('[WARN] No .env file found at ' + envFile + ' — nothing to validate.\n');
    process.exit(0);
  }

  var result = checkEnvVars(config);

  if (result.warnings.length > 0) {
    result.warnings.forEach(function (w) {
      process.stderr.write('[WARN] ' + w + '\n');
    });
  }

  if (!result.valid) {
    result.errors.forEach(function (e) {
      process.stderr.write('[ERROR] ' + e + '\n');
    });
    process.exit(1);
  }

  process.stdout.write('env-vars-check: OK\n');
  process.exit(0);
}

module.exports = { checkEnvVars, parseEnvFile, ALLOWED_VARS, DEPRECATED_VARS };
