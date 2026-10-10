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

`com.hejuno.lightpods`
