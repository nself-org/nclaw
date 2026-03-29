# Contributing to nClaw

Contributions are welcome. nClaw is an open-source AI assistant client licensed under MIT.

## Quick links

- [Wiki: Contributing](https://github.com/nself-org/claw/wiki/Contributing) — Full dev setup, code style, and testing guide
- [Wiki: Architecture](https://github.com/nself-org/claw/wiki/Architecture) — How the pieces fit together
- [GitHub Issues](https://github.com/nself-org/claw/issues) — Bug reports and feature requests

## Reporting bugs

Open a [GitHub Issue](https://github.com/nself-org/claw/issues/new) with:

- A clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Platform and version (iOS, Android, macOS, web; nClaw version; nSelf CLI version)
- Relevant logs or screenshots

For security vulnerabilities, do NOT open a public issue. See [.github/SECURITY.md](.github/SECURITY.md).

## Requesting features

Open a [GitHub Issue](https://github.com/nself-org/claw/issues/new) labeled `enhancement`. Describe:

- The problem you want to solve
- Your proposed solution
- Any alternatives you considered

## Development setup

### Prerequisites

- Flutter 3.x
- Rust stable toolchain
- Docker (for the nSelf backend)
- Xcode (iOS/macOS) or Android Studio (Android)
- nSelf CLI v1.0+ with a Pro license key

### Steps

```bash
git clone https://github.com/nself-org/claw.git
cd claw

# Build libnclaw
cd libs/libnclaw && cargo build && cd ../..

# Set up the Flutter app
cd app && flutter pub get && cd ..

# Start the backend
cd backend
nself init
nself license set nself_pro_YOURKEY
nself plugin install ai claw mux voice browser
nself build && nself start
```

See the [full setup guide](https://github.com/nself-org/claw/wiki/Getting-Started) in the wiki.

## PR guidelines

- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages:
  `feat(app): add voice input toggle`, `fix(libnclaw): handle key rotation`, etc.
- One logical change per PR
- Run `flutter analyze`, `flutter test`, and `cargo clippy` before opening a PR
- Fill out the pull request template

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
