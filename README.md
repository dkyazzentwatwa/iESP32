# iESP32

A native iOS terminal app for communicating with ESP32 microcontrollers over Bluetooth Low Energy (BLE). Built with SwiftUI, iESP32 provides a full-featured serial terminal experience using the Nordic UART Service (NUS) protocol.

## Features

### BLE Terminal
- Send commands to and receive data from ESP32 devices in real time
- Command history with up/down arrow navigation
- Configurable message buffer sizes (100 to unlimited)
- Auto-scroll with manual override
- Copy and select message text

### Device Management
- Scan for nearby BLE devices advertising the Nordic UART Service
- Auto-connect to the last used device on launch
- Auto-reconnect on unexpected disconnects
- Configurable connection and scan timeouts

### Search & Filtering
- Full-text search with regex and case-sensitive options
- Filter messages by direction (sent/received)
- Filter by time range (last hour, 24h, 7 days, or custom)
- Navigate between search results

### Connection Statistics
- Real-time RSSI signal strength with quality indicators
- 60-second RSSI history chart
- Bytes and messages sent/received
- Current and peak data rates
- Connection duration timer

### Customization
- Adjustable font size (10-24pt)
- Configurable message colors (sent, received, background)
- Light, dark, and system theme support
- Optional timestamps (absolute or relative), line numbers, and byte counts
- Text wrapping toggle
- Sound and haptic feedback for connection events

### Data Export
- Export terminal history as text, JSON, or CSV
- Optional auto-export on disconnect

### Developer Tools
- Debug mode with raw BLE packet display
- Full BLE event logging
- Diagnostic info (app version, iOS version, device model)

## Requirements

- iOS 26.2+
- iPhone or iPad with Bluetooth Low Energy support
- An ESP32 (or compatible board) running firmware that exposes the Nordic UART Service

## BLE Protocol

iESP32 communicates using the Nordic UART Service with the following UUIDs:

| Characteristic | UUID |
|---|---|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX (write) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX (notify) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Any ESP32 firmware that implements this service (e.g., using the NimBLE or Arduino BLE libraries) will work with iESP32.

## Building

1. Open `iESP32.xcodeproj` in Xcode 26.2 or later
2. Select your development team under **Signing & Capabilities**
3. Build and run on a physical device (BLE is not available in the Simulator)

## Project Structure

```
iESP32/
├── iESP32App.swift              # App entry point and SwiftData setup
├── ContentView.swift            # Main terminal UI
├── BluetoothManager.swift       # BLE communication layer
├── Models/
│   └── TerminalMessage.swift    # SwiftData message model
├── Views/
│   ├── DevicePickerView.swift   # BLE device scanner
│   └── TerminalMessageView.swift# Individual message rendering
├── Settings/
│   ├── SettingsManager.swift    # Centralized app configuration
│   ├── SettingsView.swift       # Settings navigation hub
│   ├── AppearanceSettingsView.swift
│   ├── ConnectionSettingsView.swift
│   └── AdvancedSettingsView.swift
├── Stats/
│   └── ConnectionStatsView.swift# Real-time connection statistics
├── Search/
│   ├── SearchBarView.swift      # Search UI
│   └── FilterOptionsView.swift  # Message filtering
└── Extensions/
    └── TerminalMessage+Filtering.swift
```

## License

All rights reserved.
