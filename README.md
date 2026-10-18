# LightPods

A native iOS app to control [BlazePod](https://blazepod.com) reaction training pods over Bluetooth Low Energy.

This branch replaces the earlier BLE implementation with **BlazePodKit**. BlazePodKit is a Swift package that follows the connection
and pod protocol of the official app's Android version 6.0.1. The protocol is documented in [`docs/ble-pod-protocol.md`](docs/ble-pod-protocol.md)
and [`docs/flags-and-state.md`](docs/flags-and-state.md).

> Status: step 1 (pod discovery, connection, authentication, lights, touch, battery/charger, shutdown) is done.
> The trainings ("Focus Squad Challenge", "Fast Feet", "Color Catch", …) are not implemented yet.
> The drill UI from `main` was removed on this branch, but it is still on `main`.

## Features

- **Pods**: scan, then connect and disconnect pods individually or all at once. Optional auto-connect for known pods, a pod limit, light intensity and charger polling.
- **Pod detail**: model, firmware, bootloader and serial. Light any of the 8 colours, with optional off-on-hit; identify the pod (blinks for 30 s); hit history; shut down.
- **Reaction**: lights random pods and records the reaction time measured by the pod itself, with average, best and misses.
- **Log**: raw protocol traffic (TX hex, touch notifications with the hit-filter decision, UART replies, state changes). You can filter, share and clear it.

## Architecture

```
swift_space/
├── Packages/BlazePodKit/            Swift package
│   ├── Sources/BlazePodProtocol/    pure protocol, no CoreBluetooth (unit-tested)
│   │   PodGATT           service/characteristic UUIDs
│   │   PodAdvertisement  manufacturer data (company 0x09D7): battery, charging, version, auth key
│   │   PodAuthenticator  "sea" + 4-byte challenge response (CRC-32 variant + hash mix)
│   │   PodLight          colours, intensity table, [G,B,R(,1)] LED payload, glitch guard
│   │   PodTouch          touch payload parser + hit filter (debounce / polling / off-on-hit guard)
│   │   PodUART           Nordic UART commands (chgs, tp7, xrs) and replies
│   │   PodInfo           firmware / hardware gates
│   ├── Sources/BlazePodKit/         CoreBluetooth layer
│   │   GATTOperationQueue  serial GATT operations, 3 s timeout
│   │   BlazePod            per-pod session: bring-up, auth, light API, hits
│   │   PodManager          scanning, registry, connect/retry policy, pod limit, lifecycle
│   └── Tests/BlazePodProtocolTests  incl. 53 auth reference vectors
└── Sources/                          SwiftUI app (Pods, Reaction, Log tabs)
```

### BLE summary
| Service | UUID | Use |
|---|---|---|
| Touch (also scan filter) | `50c928bd-4cb8-4c84-b745-0e58a0280cd6` | notify `50c9727e…`: touch mode and pod-measured reaction time (u32 LE ms) |
| LED | `50c97bfa-4cb8-4c84-b745-0e58a0280cd6` | write `50c912a2…`: `[G,B,R]`, or `[G,B,R,1]` to turn off on hit (fw ≥ 3.2) |
| Nordic UART | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | auth `"sea"+4 bytes`, `chgs` charger poll, `tp7`/`xrs` shutdown |
| Battery / Device Info | `180F` / `180A` | battery %, model, serial, firmware |

## Building

### Prerequisites
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Steps
```bash
cd swift_space
xcodegen generate
open BlazePodPOC.xcodeproj
# Or build and test from the command line:
xcodebuild -project BlazePodPOC.xcodeproj -scheme BlazePodPOC -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BlazePodPOC.xcodeproj -scheme BlazePodPOC -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
# Protocol tests without Xcode project:
cd Packages/BlazePodKit && swift test
```
The Simulator has no Bluetooth. Use a real iPhone to test with pods.

## What to check first on real pods

Check these in the **Log** tab:
1. **Authentication**: after connecting, you should see `auth: key=… version=…` and then `TX 6E400002 73 65 61 …`. If the pod then lights up and reports hits, it accepted the handshake.
2. **Colour order**: RED must light the pod red. The log shows `TX 50C912A2 00 00 64`.
3. **Touch**: each tap logs `RX touch … → hit(…)`. Compare the time the pod measured with the time measured on the phone.

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
