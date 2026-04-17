# Contributing

Contributions are welcome. This page covers dev setup, code conventions, testing, and the PR process.

For a shorter overview, see [CONTRIBUTING.md](../../../CONTRIBUTING.md) at the repo root.

---

## Dev Setup

### 1. Install prerequisites

- Flutter 3.x — [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)
- Rust stable — [rustup.rs](https://rustup.rs/)
- Docker — for the nSelf backend
- Xcode (macOS/iOS builds) or Android Studio (Android builds)

### 2. Clone and set up

```bash
git clone https://github.com/nself-org/claw.git
cd claw
```

### 3. Build libnclaw

```bash
cd libs/libnclaw
cargo build
```

Run Clippy before pushing Rust changes:

```bash
cargo clippy -- -D warnings
cargo test
```

### 4. Set up the Flutter app

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

### 5. Start the backend

```bash
cd backend
nself init
nself license set nself_pro_YOURKEY
nself plugin install ai claw mux voice browser
nself build
nself start
```

---

## Code Conventions

### Dart / Flutter

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) style
- Use `flutter analyze` — zero warnings policy
- Widget tests for all new screens
- Golden tests for visual components (run `flutter test --update-goldens` to regenerate baselines)
- No hardcoded strings in UI — use localization keys
- `const` constructors where possible

### Rust (libnclaw)

- `cargo clippy -- -D warnings` must pass
- No `unwrap()` in production code — use `?` operator or explicit error handling
- All public types and functions documented with `///` doc comments
- Unit tests for all non-trivial logic
- No `unsafe` blocks without a comment explaining why they are sound

### General

- No hardcoded server URLs — all endpoints come from user configuration
- No credentials or secrets in source code
- Follow conventional commits for commit messages (see below)

---

## Commit Message Format

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`

Scopes: `app`, `ios`, `android`, `desktop`, `libnclaw`, `backend`, `ci`

Examples:
```
feat(app): add voice input toggle in settings
fix(libnclaw): handle decryption failure on key rotation
docs(wiki): update architecture diagram
chore(ci): add Android build to release workflow
```

---

## Testing

| Layer | Command | What it covers |
|-------|---------|---------------|
| Rust unit | `cargo test` (in `libs/libnclaw/`) | FFI types, encryption, protocol |
| Flutter unit | `flutter test` (in `app/`) | Business logic, state management |
| Flutter widget | `flutter test` (in `app/`) | Widget rendering, interactions |
| Flutter golden | `flutter test` (with `--update-goldens` to refresh) | Visual regression |
| Static analysis | `flutter analyze` / `cargo clippy` | Code quality |

Before opening a PR, run all checks for the layers you touched:

```bash
# Rust
cd libs/libnclaw && cargo clippy -- -D warnings && cargo test

# Flutter
cd app && flutter analyze && flutter test
```

---

## Pull Request Process

1. Fork the repo and create a branch from `main`
2. Branch naming: `feat/`, `fix/`, `docs/`, `chore/` prefix
3. Make your changes. Keep each PR to one logical change
4. Run the relevant tests (see above)
5. Open a PR using the [PR template](../.github/PULL_REQUEST_TEMPLATE.md)
6. A maintainer will review within a few days

PRs that add new Pro plugin dependencies will not be accepted. The client must work with the currently-required plugins (`ai`, `claw`, `mux`) plus the optional ɳClaw-bundle plugins (`claw-web`, `voice`, `browser`, `google`, `notify`, `cron`). See [Plugin Requirements](https://github.com/nself-org/claw/wiki/Plugin-Requirements).

---

## Reporting Issues

Use [GitHub Issues](https://github.com/nself-org/claw/issues). For security issues, see [SECURITY.md](../SECURITY.md) — do not open a public issue.
