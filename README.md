# LightPods

A native iOS app to control [BlazePod](https://blazepod.com) reaction training pods over Bluetooth Low Energy — without the official subscription app.

## Features

- **Scan & Connect** — Discover nearby BlazePods via BLE and connect to multiple pods simultaneously
- **Pod Control** — Light up pods in any color (red, green, blue, white, yellow, purple, orange) with auto-off-on-tap
- **Reaction Drill** — Random drill mode that lights pods one at a time and records reaction times from the pod's own hardware timer
- **Statistics** — Track total hits, average/best/worst reaction times per drill session

## BLE Protocol

The BlazePod BLE protocol is reverse-engineered from:
- [sasodoma/blazepod-hacking](https://github.com/sasodoma/blazepod-hacking)
- [Snerls/blazepod](https://github.com/Snerls/blazepod)

### Services & Characteristics
| Service | UUID | Purpose |
|---------|------|---------|
| UART | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | Authentication handshake |
| Color | `50c97bfa-4cb8-4c84-b745-0e58a0280cd6` | Set pod LED color |
| Tap | `50c928bd-4cb8-4c84-b745-0e58a0280cd6` | Tap notifications |

## Building

### Prerequisites
- Xcode 26+ (with iOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Steps
```bash
cd swift_space
xcodegen generate
open BlazePodPOC.xcodeproj
# Or build from CLI:
xcodebuild -project BlazePodPOC.xcodeproj -scheme BlazePodPOC -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

### CI (GitHub Actions)
The repo includes `.github/workflows/build.yml` for a self-hosted Mac Mini M4 runner.

### Fastlane
```bash
bundle exec fastlane build   # Simulator build
bundle exec fastlane test    # Run tests
```

## What to Test First on Real Hardware

1. **BLE Discovery** — Verify BlazePods appear in the scan list (check manufacturer data filtering)
2. **Authentication** — The auth handshake is the most critical/fragile part. Watch console logs for the auth payload bytes.
3. **Color Commands** — Try each color; verify [G,B,R] byte order is correct for your firmware
4. **Tap Detection** — Tap a lit pod and confirm the reaction time appears
5. **Multi-Pod** — Connect 2+ pods and run a drill

## Known Unknowns

- **Firmware compatibility** — The auth algorithm was reverse-engineered from specific firmware versions. Newer BlazePod firmware may use a different handshake or change service UUIDs.
- **Auth algorithm correctness** — The XOR + offset computation may have edge cases on different manufacturer data patterns. If auth fails, check the raw manufacturer data bytes in the scan list.
- **BLE behavior across iOS versions** — CoreBluetooth behavior around background scanning, connection limits, and characteristic discovery can vary between iOS releases.
- **Pod hardware timer accuracy** — Reaction times come from the pod's own clock (bytes 1-4 of tap notification). Timer start/resolution may vary by firmware.
- **Maximum simultaneous connections** — iOS typically supports ~7 BLE peripherals. Real-world limits depend on the Bluetooth chipset and other connected accessories.

## Architecture

```
Sources/
├── App/          # App entry point
├── Models/
│   ├── PodDevice.swift      # Pod model + color enum
│   ├── BLEManager.swift     # CoreBluetooth central manager
│   └── DrillManager.swift   # Random drill logic
└── Views/
    ├── ContentView.swift    # Tab container
    ├── ScanView.swift       # BLE discovery UI
    ├── PodsView.swift       # Connected pod cards
    └── DrillView.swift      # Reaction drill UI
```

## License

MIT

## Bundle Identifier

`com.TEAMID.LightPods` (where TEAMID is your Apple Developer Team ID)

## CI/CD Setup (GitHub Actions)

This project uses the same CI/CD pattern as [LoopWorkspace](https://github.com/LoopKit/LoopWorkspace) for browser-based builds to TestFlight.

### Workflows

| # | Workflow | Trigger | Purpose |
|---|---------|---------|---------|
| 1 | **Validate Secrets** | Manual / called by others | Validates GH_PAT, Match-Secrets repo, Fastlane API key, TEAMID |
| 2 | **Add Identifiers** | Manual | Creates/updates App ID in App Store Connect with Bluetooth capability |
| 3 | **Create Certificates** | Manual / called by build | Manages Distribution certs via Fastlane Match, auto-nuke if expired |
| 4 | **Build LightPods Manual** | Manual | Full build → sign → TestFlight upload |
| 4 | **Build LightPods Auto** | Scheduled (Sunday) or manual | Monthly auto-build (2nd Sunday) |

### Required Secrets

Set these in **Settings → Secrets and variables → Actions** on your fork:

| Secret | Description |
|--------|-------------|
| `GH_PAT` | GitHub Personal Access Token with `repo` + `workflow` scopes |
| `TEAMID` | Your 10-character Apple Developer Team ID |
| `FASTLANE_KEY_ID` | App Store Connect API Key ID |
| `FASTLANE_ISSUER_ID` | App Store Connect API Issuer ID |
| `FASTLANE_KEY` | App Store Connect API Key content (`.p8` file contents) |
| `MATCH_PASSWORD` | Encryption password for the Match-Secrets repository |

### Optional Variables

Set these in **Settings → Secrets and variables → Actions → Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `SCHEDULED_BUILD` | `true` | Set to `false` to disable scheduled builds |
| `ENABLE_NUKE_CERTS` | `false` | Set to `true` to allow automatic certificate renewal |
| `FORCE_NUKE_CERTS` | `false` | Set to `true` to force certificate nuke on next run |

### First-Time Setup

1. Fork this repository (or push to your own org)
2. Configure all required secrets
3. Run **1. Validate Secrets** to verify configuration
4. Run **2. Add Identifiers** to create the App ID
5. Run **3. Create Certificates** to set up signing
6. Run **4. Build LightPods Manual** to build and upload to TestFlight
