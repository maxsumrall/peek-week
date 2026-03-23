# Peek Week

macOS shows the date in the menu bar, but not the week number. Sometimes you just want to glance up and see **W13**.

Peek Week is a tiny native menu bar app that fixes that. Click it to see how much of the quarter and year is left.

<img src="docs/preview.png" width="350" alt="Peek Week">

## Install

1. Download **peek-week-macos.dmg** from the [latest release](../../releases/latest)
2. Drag **Peek Week** to **Applications**
3. Launch — it starts at login automatically

> macOS may warn about an unsigned app. Right-click → Open the first time.

## Build from source

```bash
git clone https://github.com/maxsumrall/peek-week.git
cd peek-week
./scripts/build-app.sh
open "build/Peek Week.app"
```

## License

MIT
