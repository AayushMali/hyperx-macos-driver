# HyperX Control for macOS

A lightweight, native macOS driver and control utility for the HyperX Pulsefire Haste 2 Core Wireless mouse. Works seamlessly across both Bluetooth and 2.4GHz USB Dongle connections.

## Features

- **Side Button Modes & Segment Navigation**:
  - **Fast Double-Click for Segment Review (`[` / `]`)**: Rapidly double-clicking the top side button sends `]` (Next Segment) and double-clicking the bottom side button sends `[` (Previous Segment) while keeping single-click for Tab Switching or History.
  - **Chrome / Browser Tab Switcher**: Single-click switches between adjacent browser tabs (`Control + Tab` / `Control + Shift + Tab`).
  - **History Navigation**: Moves Back and Forward in browser and Finder history (`Cmd + [` and `Cmd + ]`).
  - **Segment Review (`[` / `]` Single Click)**: Dedicated review mode where a single click directly sends `[` or `]`.
  - **Disabled**: Standard native mouse buttons 4 and 5.
- **Cursor Acceleration Slider**: Interactive volume-style slider in the menu bar to adjust sensitivity from 0.50x to 3.00x in real time.
- **Scroll Wheel Inversion**: Invert mouse wheel direction without affecting the MacBook trackpad natural scroll setting.
- **Dual Connection Support**: Automatically detects and handles switching between Bluetooth Low Energy and 2.4GHz USB Dongle.
- **Battery Reporting**: Reads and displays current battery percentage from macOS Bluetooth subsystem.
- **Menu Bar App**: Clean status bar icon showing connection type, battery, and quick toggles.
- **CLI & Daemon Modes**: Can run headlessly in the background or via system launchd.

## Building and Running

### 1. Compile

To build the command line binary and the Menu Bar application:

```bash
make app
```

This generates:
- `hyperx-control` (CLI binary)
- `HyperXControl.app` (macOS Application bundle)

### 2. Check Device Status

To quickly inspect connection and battery status:

```bash
./hyperx-control --status
```

Example output:
```text
Device: HyperX Pulsefire Haste 2 Core Wireless
Transport: Bluetooth Low Energy
Vendor ID: 0x03F0
Product ID: 0x08B5
Battery: 100%
```

### 3. Run Menu Bar App

Double-click `HyperXControl.app` or launch it from terminal:

```bash
open HyperXControl.app
```

A mouse icon will appear in your top menu bar with status and toggles.

### 4. Run as Background Daemon

To run headlessly without menu bar UI:

```bash
./hyperx-control --daemon
```

To automatically start on login via launchd:

```bash
cp com.hyperx.control.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.hyperx.control.plist
```

## Configuration

Settings are stored in `~/.config/hyperx/config.json`:

```json
{
  "sideButtonMode": "tabs",
  "doubleClickSegments": true,
  "smoothScroll": true,
  "invertScroll": false,
  "scrollMultiplier": 1.0,
  "cursorMultiplier": 1.0
}
```

## Permissions

The app uses `CGEventTap` to capture side buttons and scroll events. macOS requires Accessibility permissions:
1. Open **System Settings** -> **Privacy & Security** -> **Accessibility**.
2. Add and allow `Terminal` (if running via terminal) or `HyperXControl.app`.
# hyperx-macos-driver
