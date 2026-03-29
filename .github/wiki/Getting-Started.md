# Getting Started

## Prerequisites

### nSelf CLI and Pro license

nClaw requires a self-hosted nSelf backend with Pro plugins.

1. Install nSelf CLI v1.0+:
   ```bash
   brew install nself-org/nself/nself
   ```

2. Obtain a Pro license key from [nself.org/pricing](https://nself.org/pricing) ($1.99/mo or $19.99/yr). The key has the format `nself_pro_` followed by 32+ characters.

3. Set the license:
   ```bash
   nself license set nself_pro_YOURKEY
   ```

### Flutter

Install Flutter 3.x via the [official installer](https://docs.flutter.dev/get-started/install).

Verify:
```bash
flutter doctor
```

### Rust

Install the Rust stable toolchain via [rustup](https://rustup.rs/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Docker

Docker is required to run the nSelf backend. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine.

### Platform tools

- **iOS/macOS:** Xcode (latest stable) from the Mac App Store
- **Android:** Android Studio with NDK installed

---

## Backend Setup

```bash
cd backend

# Initialize nSelf project
nself init

# Install required Pro plugins
nself plugin install ai claw mux voice browser

# Generate docker-compose and config
nself build

# Start the backend
nself start
```

The backend will start at:
- GraphQL API: `http://localhost:8080/v1/graphql`
- Auth: `http://localhost:4000`
- Storage: `http://localhost:9000`

See [backend/README.md](../../../backend/README.md) for the full self-hosting guide.

---

## Clone the repo

```bash
git clone https://github.com/nself-org/claw.git
cd claw
```

---

## Build libnclaw (Rust FFI)

```bash
cd libs/libnclaw
cargo build --release
```

---

## Run the Flutter app

```bash
cd app
flutter pub get
```

### iOS

```bash
flutter run -d ios
```

Requires Xcode and an iOS simulator or physical device.

### Android

```bash
flutter run -d android
```

Requires an Android emulator or physical device with USB debugging enabled.

### macOS

```bash
flutter run -d macos
```

Requires macOS 12+ and Xcode.

### Web

```bash
flutter run -d chrome
```

---

## First launch

When the app starts, it will prompt for your nSelf backend URL. Enter the URL of your running nSelf instance (e.g., `http://localhost:4000` for local development, or your server's domain for a remote deployment).

After connecting, sign in using the credentials you configured in your nSelf backend.

---

## Native clients

### iOS/macOS (SwiftUI)

```bash
open apps/ios/nClaw.xcodeproj
```

Build and run from Xcode. Targets both iOS and macOS via Mac Catalyst.

### Android (Kotlin)

Open `apps/android/` in Android Studio and run from there.
