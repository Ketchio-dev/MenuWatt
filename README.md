# MenuWatt ⚡🐱

A lightweight macOS menu bar app that monitors your battery, CPU, memory, and storage — with a cute animated pixel cat that reacts to your charging state.

Inspired by [RunCat](https://kyome.io/runcat/index.html).

## Features

- **Animated menu bar sprite** — a pixel cat that changes behavior:
  - 🏃 Runs fast while charging
  - 🧘 Sits idle on adapter (fully charged)
  - 😴 Sleeps on battery
- **Live wattage display** in the menu bar (when supported by hardware)
- **System dashboard** with real-time metrics:
  - Battery: percentage, charge rate, cycle count, temperature, power source
  - CPU: usage breakdown (system/user/idle) with history graph
  - Memory: pressure level, used/wired/compressed/cached/swap
  - Storage: used vs total with visual bar

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (full Xcode not required)

## Installation

### Option 1: Build & Run directly

```bash
git clone https://github.com/Ketchio-dev/MenuWatt.git
cd MenuWatt
swift run
```

### Option 2: Build as `.app` bundle

```bash
git clone https://github.com/Ketchio-dev/MenuWatt.git
cd MenuWatt
./scripts/build-app.sh
open .build/ChargeCat.app
```

You can drag the built `.app` to your Applications folder to keep it.

## Usage

Once launched, MenuWatt appears in your menu bar with a small animated cat and your battery percentage. Click the icon to open the system monitor dashboard.

The cat's animation reflects your Mac's charging state:
| State | Animation |
|-|-|
| Charging | Cat runs (speed varies with charge rate) |
| On adapter (full) | Cat sits idle |
| On battery | Cat sleeps |

## Tech Stack

- **Swift 6.1** with Swift Package Manager
- **SwiftUI** for the dashboard panel
- **AppKit** for menu bar integration
- **IOKit** for battery data (no third-party dependencies)

## License

MIT
