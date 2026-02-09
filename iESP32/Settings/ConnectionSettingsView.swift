//
//  ConnectionSettingsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            // Timeout Settings
            Section {
                Picker("Connection timeout", selection: $settings.connectionTimeout) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }

                Picker("Scan duration", selection: $settings.scanDuration) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                }
            } header: {
                Text("Timeouts")
            } footer: {
                Text("Connection timeout is how long to wait when connecting to a device. Scan duration is how long to scan for devices.")
            }

            // Auto-Reconnect Section
            Section {
                Toggle("Auto-reconnect", isOn: $settings.autoReconnect)

                Toggle("Remember last device", isOn: $settings.rememberLastDevice)

                if settings.rememberLastDevice && !settings.lastDeviceName.isEmpty {
                    HStack {
                        Text("Last device:")
                            .foregroundColor(.secondary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(settings.lastDeviceName)
                                .font(.caption)
                            Text(settings.lastDeviceUUID)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Reconnection")
            } footer: {
                Text("Auto-reconnect will attempt to reconnect if the connection is lost. Remember last device will automatically connect to the last used device on app launch.")
            }

            // Device List Settings
            Section {
                Toggle("Show RSSI in device list", isOn: $settings.showRSSIInList)
            } header: {
                Text("Device List")
            } footer: {
                Text("RSSI (Received Signal Strength Indicator) shows the signal strength of nearby devices.")
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }
}
