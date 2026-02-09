//
//  SettingsManager.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    // MARK: - Appearance Settings
    @AppStorage("fontSize") var fontSize: Double = 14.0
    @AppStorage("theme") var theme: String = "system" // system, light, dark
    @AppStorage("sentMessageColor") var sentMessageColorHex: String = "00FF00" // Green
    @AppStorage("receivedMessageColor") var receivedMessageColorHex: String = "FFFFFF" // White
    @AppStorage("backgroundColor") var backgroundColorHex: String = "000000" // Black
    @AppStorage("showTimestamps") var showTimestamps: Bool = false
    @AppStorage("timestampFormat") var timestampFormat: String = "HH:mm:ss" // HH:mm:ss, HH:mm:ss.SSS, relative

    // MARK: - Terminal Behavior
    @AppStorage("autoScroll") var autoScroll: Bool = true
    @AppStorage("clearOnConnect") var clearOnConnect: Bool = false
    @AppStorage("messageBufferSize") var messageBufferSize: Int = 1000 // 100, 500, 1000, 5000, -1 (unlimited)
    @AppStorage("textWrapping") var textWrapping: Bool = true
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = false

    // MARK: - Connection Settings
    @AppStorage("connectionTimeout") var connectionTimeout: Int = 10 // seconds
    @AppStorage("autoReconnect") var autoReconnect: Bool = false
    @AppStorage("rememberLastDevice") var rememberLastDevice: Bool = false
    @AppStorage("lastDeviceUUID") var lastDeviceUUID: String = ""
    @AppStorage("lastDeviceName") var lastDeviceName: String = ""
    @AppStorage("scanDuration") var scanDuration: Int = 10 // seconds
    @AppStorage("showRSSIInList") var showRSSIInList: Bool = true

    // MARK: - Notifications & Sounds
    @AppStorage("connectionSound") var connectionSound: Bool = true
    @AppStorage("disconnectionAlert") var disconnectionAlert: Bool = true
    @AppStorage("messageReceivedSound") var messageReceivedSound: Bool = false
    @AppStorage("hapticFeedback") var hapticFeedback: Bool = true

    // MARK: - Data Management
    @AppStorage("exportFormat") var exportFormat: String = "text" // text, json, csv
    @AppStorage("commandHistorySize") var commandHistorySize: Int = 50 // 25, 50, 100, 200
    @AppStorage("autoExportOnDisconnect") var autoExportOnDisconnect: Bool = false

    // MARK: - Developer Options
    @AppStorage("showRawDataPackets") var showRawDataPackets: Bool = false
    @AppStorage("logAllBLEEvents") var logAllBLEEvents: Bool = false
    @AppStorage("debugMode") var debugMode: Bool = false
    @AppStorage("showMessageByteCount") var showMessageByteCount: Bool = false

    // MARK: - Computed Properties for Colors
    var sentMessageColor: Color {
        Color(hex: sentMessageColorHex) ?? .green
    }

    var receivedMessageColor: Color {
        Color(hex: receivedMessageColorHex) ?? .white
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex) ?? .black
    }

    // MARK: - Reset to Defaults
    func resetToDefaults() {
        fontSize = 14.0
        theme = "system"
        sentMessageColorHex = "00FF00"
        receivedMessageColorHex = "FFFFFF"
        backgroundColorHex = "000000"
        showTimestamps = true
        timestampFormat = "HH:mm:ss"

        autoScroll = true
        clearOnConnect = false
        messageBufferSize = 1000
        textWrapping = true
        showLineNumbers = false

        connectionTimeout = 10
        autoReconnect = false
        rememberLastDevice = false
        lastDeviceUUID = ""
        lastDeviceName = ""
        scanDuration = 10
        showRSSIInList = true

        connectionSound = true
        disconnectionAlert = true
        messageReceivedSound = false
        hapticFeedback = true

        exportFormat = "text"
        commandHistorySize = 50
        autoExportOnDisconnect = false

        showRawDataPackets = false
        logAllBLEEvents = false
        debugMode = false
        showMessageByteCount = false
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)

        return String(format: "%02X%02X%02X", r, g, b)
    }
}
