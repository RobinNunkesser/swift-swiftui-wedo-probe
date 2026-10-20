# WedoProbe (SwiftUI + CoreBluetooth)

Native macOS SwiftUI app to validate LEGO WeDo BLE behavior without Shiny/.NET.

## Why this app exists

If `1623/1624` notifications, probe writes, or battery fallback fail in the MAUI app, this app helps answer one question quickly:

- Do the same operations work with native CoreBluetooth on macOS?

## Features

- BLE scan with optional WeDo marker by advertised hub service `1623`
- Connect/disconnect to selected peripheral
- Discover services and characteristics
- Subscribe to hub characteristic `1624` (notify/indicate)
- Send hub probe frames on `1624`
- Try battery read via
  - standard service `180F/2A19`
  - LPF2 hub property request on `1624`
- Live protocol log with raw hex frames

## Quick Start

1. Generate the Xcode project:

```bash
cd artifacts/consumers/production/swiftui-wedo-probe
xcodegen generate
```

2. Open the project:

```bash
open WedoProbe.xcodeproj
```

3. In Xcode:

- Select scheme `WedoProbe`
- Target: `My Mac`
- Run

4. In the app:

- `Start Scan`
- Select your hub
- `Connect`
- `Subscribe 1624`
- `Probe 1624`
- `Read Battery`

## Interpretation guide

- If native app succeeds for `1623/1624` while MAUI fails, root cause is likely in the abstraction/runtime layer.
- If native app shows same failures, issue is likely device/protocol sequencing or platform behavior.
