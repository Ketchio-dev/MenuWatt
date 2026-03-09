<p align="center">
  <h1 align="center">MenuWatt ⚡🐱</h1>
  <p align="center">
    A native macOS menu bar app featuring Boochi, the running pixel character, plus live battery, CPU, memory, and storage stats.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/swift-6.2-orange?style=flat-square" alt="Swift">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
  </p>
</p>

---

## What Is MenuWatt?

MenuWatt lives in your menu bar as a tiny utility app. Its running character is Boochi, and the app gives you a quick view of live power usage plus a compact dashboard for battery, CPU, memory, and storage details.

Inspired by [RunCat](https://kyome.io/runcat/index.html), MenuWatt is built in Swift with zero runtime dependencies. Tests use the official `swift-testing` package.

## Features

- **Animated pixel boochi**: runs in every battery state, with speed driven by current system load.
- **Live wattage in the menu bar**: surfaces current power input or system load without opening the panel.
- **Compact system dashboard**: shows battery, CPU, memory, and storage metrics in one menu bar panel.
- **Native macOS app**: SwiftUI + AppKit, no Electron, no web wrapper, no background services.

| Charging State | Boochi Behavior |
|-|-|
| Charging | Runs fast (speed scales with charge rate) |
| Plugged in (full) | Runs |
| On battery | Runs |

The dashboard includes:

| Metric | Details |
|-|-|
| Battery | Percentage, charge rate, cycle count, temperature, power source, ETA |
| CPU | Total/system/user/idle usage with live history graph |
| Memory | Pressure level, used/wired/compressed/cached/swap breakdown |
| Storage | Used vs total with visual progress bar |

## Architecture

MenuWatt is split into three targets:

| Target | Responsibility |
|-|-|
| `MenuWattCore` | Shared models, snapshots, formatting helpers, and sampling contracts |
| `MenuWattSystem` | macOS-specific live readers for battery and system metrics |
| `MenuWatt` | Menu bar UI, animation, presentation mapping, and app lifecycle |

## Install

### For Most Users

Download the latest app bundle from GitHub Releases, open it, and move `MenuWatt.app` into your `Applications` folder.

When you publish releases, link this section to:

```text
https://github.com/Ketchio-dev/MenuWatt/releases/latest
```

Recommended release assets:

- `MenuWatt.dmg` for the easiest drag-and-drop install
- `MenuWatt.zip` as a fallback

### For Developers

If you want to run MenuWatt directly from source:

- macOS 13 or later
- Xcode Command Line Tools

```bash
xcode-select --install
swift run
```

### Automated Install

If you want a one-command installer, provide an `install.sh` script that downloads the latest notarized release and installs `MenuWatt.app` into `/Applications`.

Example usage:

```bash
curl -fsSL https://example.com/menuwatt/install.sh | sh
```

This should be treated as a convenience path for power users, not the primary install method.

### Build the App Bundle Locally

If you are packaging or testing the app bundle yourself:

```bash
./scripts/build-app.sh
open .build/MenuWatt.app
```

### Run Tests

```bash
swift test
```

## How It Works

MenuWatt reads battery data directly through Apple's **IOKit** framework with no runtime dependencies, background daemons, or network calls. System metrics (CPU, memory, storage) are gathered via `host_statistics` and filesystem APIs.

## Tech Stack

| Component | Technology |
|-|-|
| UI Framework | SwiftUI + AppKit |
| Battery Data | IOKit (IOPSCopyPowerSourcesInfo) |
| CPU/Memory | Mach host_statistics64 |
| Build System | Swift Package Manager |
| Test Framework | swift-testing |
| Min Deployment | macOS 13.0 (Ventura) |

## Notes

- MenuWatt is a menu bar utility, so it launches as an accessory app rather than a dock app.
- The generated bundle name is `MenuWatt.app`.
- The best default distribution is a notarized DMG or ZIP on GitHub Releases.
- `curl | sh` is best kept as an optional install path for CLI-friendly users.
- If you plan to publish releases on GitHub, add screenshots or a short demo GIF near the top of this README.

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE)
