<p align="center">
  <h1 align="center">MenuWatt ⚡🐱</h1>
  <p align="center">
    A tiny macOS menu bar app with an animated pixel cat that monitors your Mac's battery, CPU, memory, and storage in real time.
  </p>
  <p align="center">
    <a href="https://github.com/Ketchio-dev/MenuWatt/releases/latest"><img src="https://img.shields.io/github/v/release/Ketchio-dev/MenuWatt?style=flat-square&color=blue" alt="Release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/swift-6.1-orange?style=flat-square" alt="Swift">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
  </p>
</p>

---

## What is MenuWatt?

MenuWatt lives in your menu bar as a small pixel cat. The cat **reacts to your charging state** — it runs while charging, sits idle on adapter, and sleeps on battery. Click the icon to open a dashboard with real-time system metrics.

Inspired by [RunCat](https://kyome.io/runcat/index.html), built entirely in Swift with zero dependencies.

## Features

🐱 **Animated Pixel Cat** — changes behavior based on charging state

| Charging State | Cat Behavior |
|-|-|
| Charging | Runs fast (speed scales with charge rate) |
| Plugged in (full) | Sits idle |
| On battery | Sleeps |

⚡ **Live Wattage** — shows real-time power input (W) in the menu bar

📊 **System Dashboard** — click the menu bar icon to see:

| Metric | Details |
|-|-|
| Battery | Percentage, charge rate, cycle count, temperature, power source, ETA |
| CPU | Total/system/user/idle usage with live history graph |
| Memory | Pressure level, used/wired/compressed/cached/swap breakdown |
| Storage | Used vs total with visual progress bar |

## Install

### Homebrew (recommended)

```bash
brew install Ketchio-dev/tap/menuwatt
```

### Direct Download

Download the latest `.zip` from [**Releases**](https://github.com/Ketchio-dev/MenuWatt/releases/latest), unzip, and drag `ChargeCat.app` into your **Applications** folder.

### Build from Source

```bash
git clone https://github.com/Ketchio-dev/MenuWatt.git
cd MenuWatt

# Run directly
swift run

# Or build a .app bundle
./scripts/build-app.sh
open .build/ChargeCat.app
```

> **Requirements:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

## How It Works

MenuWatt reads battery data directly through Apple's **IOKit** framework — no third-party libraries, no background daemons, no network calls. System metrics (CPU, memory, storage) are gathered via `host_statistics` and `statvfs`.

## Tech Stack

| Component | Technology |
|-|-|
| UI Framework | SwiftUI + AppKit |
| Battery Data | IOKit (IOPSCopyPowerSourcesInfo) |
| CPU/Memory | Mach host_statistics64 |
| Build System | Swift Package Manager |
| Min Deployment | macOS 13.0 (Ventura) |

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE)
