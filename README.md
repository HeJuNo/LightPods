# LightPods

A native iOS app to control [BlazePod](https://blazepod.com) reaction training pods over Bluetooth Low Energy.

This branch replaces the earlier BLE implementation with **BlazePodKit**. BlazePodKit is a Swift package that follows the connection
and pod protocol of the official app's Android version 6.0.1. The protocol is documented in [`docs/ble-pod-protocol.md`](docs/ble-pod-protocol.md)
and [`docs/flags-and-state.md`](docs/flags-and-state.md).

> Status: pod setup and the trainings *Color Catch*, *Plank Focus Challenge*, *Fast Feet* and the
> configurable *Random* drill are implemented. How the original engines work is in [`docs/drill-engines.md`](docs/drill-engines.md).

## Features

- **Drills.** Built-in drills plus your own. Every drill can be configured: stations, pods, players, colours per player, competition mode, lights out (hit / timeout / both), light delay (none / fixed / random), duration (time / hit count / either) and cycles with rest. Save any change as a new drill.
- **Per-drill pods and players.** Pick and order the pods a drill uses (station order), flash them to find them, and name the players.
- **Live run.** 3-2-1 countdown, a timer ring, a live map of the lit pods, a scoreboard per player, haptics and sounds. Cycles have a rest countdown between them.
- **Results.** Hits, average and best reaction time, accuracy, a reaction-time chart per player, and the winner in multi-player drills.
- **Pods.** The pod counter at the top right opens the pod settings:
  - **Auto-connect** connects your pods and any newly switched-on pod.
  - My pods and nearby pods, with battery and signal.
  - Identify, light test, firmware info, shutdown, brightness, and a Bluetooth log.

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
│   │   PodManager          scanning, registry, connect/retry policy, auto-connect, pod limit, lifecycle
│   ├── Sources/BlazePodDrills/      drill model + engines, no CoreBluetooth (unit-tested on virtual time)
│   │   DrillDefinition   settings, ranges, built-in drills (Codable)
│   │   DrillSession      countdown, cycles, rest, scoring; Random and Focus station engines
│   │   DrillScheduler    main-queue and manual (test) clocks
│   └── Tests/                       protocol tests (53 auth vectors) + drill engine tests
└── Sources/                          SwiftUI app
    ├── App/      entry point, debug demo mode
    ├── Design/   theme, glowing pod view, steppers, pickers
    ├── Drills/   library, setup, live run, results, drill store
    └── Pods/     pod controller, pod settings, pod detail, log
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
The Simulator has no Bluetooth. Use a real iPhone to test with pods. For UI work, Debug builds
accept the launch argument `-demo`: it simulates 24 pods with a virtual athlete. Add `-drill <n>` to open
drill *n*, and `-autostart` to start it.

## What to check first on real pods

Check these in the Bluetooth log (pod settings → Advanced → Bluetooth log):
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
