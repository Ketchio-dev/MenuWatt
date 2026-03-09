# ChargeCat

Runcat-inspired macOS menu bar app that animates a small sprite and opens a live system monitor for your Mac.

## What it does

- Shows an animated menu bar sprite.
- Reads battery percentage and charging state using `IOKit`.
- Shows real-time power input in watts in the menu bar when the hardware exposes it.
- Opens a menu with CPU usage, memory pressure, storage usage, battery metrics, and a mini history graph.
- Uses faster animation while charging, idle animation on adapter, and sleepy animation on battery.

## Run

```bash
swift run
```

## Build a local `.app`

```bash
./scripts/build-app.sh
open .build/ChargeCat.app
```

## Notes

- This project uses Swift Package Manager so it can build with Command Line Tools only.
- If you later install full Xcode, you can open `Package.swift` directly in Xcode.
