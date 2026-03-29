# Security Policy

## Supported versions

Security fixes are applied to the latest release only.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

## Scope

This policy covers:

- The nClaw client app (`app/`, `apps/ios/`, `apps/android/`, `apps/desktop/`)
- The `libnclaw` Rust FFI library (`libs/libnclaw/`)

**Out of scope:**

- The nSelf backend itself — report backend issues to the [nSelf security team](https://nself.org/security)
- nSelf Pro plugins (nself-ai, nself-claw, nself-mux, nself-voice, nself-browser)
- Your self-hosted server infrastructure

## Reporting a vulnerability

Do NOT open a public GitHub issue for security vulnerabilities.

Email: **security@nself.org**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fix (optional)

We will acknowledge your report within 48 hours.

## Response timeline

| Severity | Patch target |
|----------|-------------|
| Critical (remote code execution, auth bypass, E2E encryption break) | 7 days |
| High (data exposure, privilege escalation) | 14 days |
| Medium | 30 days |
| Low / informational | Next scheduled release |

We will keep you updated as we investigate and patch. We ask that you do not disclose the vulnerability publicly until a patch is available.

## Responsible disclosure

We appreciate responsible disclosure. If you follow this policy, we will:

- Acknowledge your contribution in the release notes (unless you prefer to remain anonymous)
- Not take legal action against you for good-faith security research
