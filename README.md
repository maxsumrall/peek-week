# Peek Week

A tiny native macOS menu bar app that shows the current **ISO week number**.

Glance up, see `W13`. Click it to peek at quarter and year progress.

<img src="docs/preview.png" width="350" alt="Peek Week">

## Features

- **Menu bar**: current ISO 8601 week number (`W13`)
- **Click** to see a popover with:
  - Week number + quarter badge
  - Time remaining in the quarter and year (`1w 2d left`)
  - Progress bars with percentage
- **Right-click** to quit
- Launches at login automatically
- Single file, zero dependencies, native SwiftUI

## Install

1. Download **peek-week-macos.zip** from the [latest release](../../releases/latest)
2. Unzip and drag **Peek Week.app** to `/Applications`
3. Launch it
4. macOS may warn about an unsigned app — **right-click → Open** the first time

## Build from source

```bash
git clone https://github.com/maxsumrall/peek-week.git
cd peek-week
./scripts/build-app.sh
open "build/Peek Week.app"
```

Requires Xcode command-line tools (`xcode-select --install`).

## How it works

Everything is in one file: [`Sources/PeekWeek/main.swift`](Sources/PeekWeek/main.swift).

- `NSStatusItem` for the menu bar text
- `NSPopover` with a SwiftUI view for the click panel
- ISO 8601 calendar for week numbering
- Gregorian calendar for quarter/year progress
- `SMAppService` for launch-at-login (macOS 13+)
- Refreshes on day change, system wake, and clock changes

## Design choices

- **ISO 8601** weeks — what most people mean by "W13"
- **Calendar days** for remaining time — not business days
- **Native AppKit/SwiftUI** — no Electron, no script host, no third-party dependencies
- **No settings, no preferences, no feature creep**

## Requirements

macOS 13 (Ventura) or later.

## License

MIT
