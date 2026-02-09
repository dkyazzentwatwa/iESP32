//
//  AppearanceSettingsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            // Font Size Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Size: \(Int(settings.fontSize))pt")
                        .font(.headline)

                    Slider(value: $settings.fontSize, in: 10...24, step: 1) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Text("10")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("24")
                            .font(.caption)
                    }

                    // Preview
                    Text("Sample terminal text")
                        .font(.system(size: settings.fontSize, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(4)
                }
            } header: {
                Text("Font")
            }

            // Theme Section
            Section {
                Picker("Theme", selection: $settings.theme) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max.fill").tag("light")
                    Label("Dark", systemImage: "moon.fill").tag("dark")
                }
                .pickerStyle(.inline)
            } header: {
                Text("Theme")
            } footer: {
                Text("System theme follows your device settings")
            }

            // Terminal Colors Section
            Section {
                ColorPicker("Sent messages", selection: Binding(
                    get: { settings.sentMessageColor },
                    set: { settings.sentMessageColorHex = $0.toHex() ?? "00FF00" }
                ))

                ColorPicker("Received messages", selection: Binding(
                    get: { settings.receivedMessageColor },
                    set: { settings.receivedMessageColorHex = $0.toHex() ?? "FFFFFF" }
                ))

                ColorPicker("Background", selection: Binding(
                    get: { settings.backgroundColor },
                    set: { settings.backgroundColorHex = $0.toHex() ?? "000000" }
                ))

                // Preview
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("[12:34:56]")
                            .foregroundColor(.secondary)
                        Text(">>")
                        Text("Hello ESP32")
                    }
                    .font(.system(size: settings.fontSize, design: .monospaced))
                    .foregroundColor(settings.sentMessageColor)

                    HStack {
                        Text("[12:34:57]")
                            .foregroundColor(.secondary)
                        Text("<<")
                        Text("Hi from device!")
                    }
                    .font(.system(size: settings.fontSize, design: .monospaced))
                    .foregroundColor(settings.receivedMessageColor)
                }
                .padding(12)
                .background(settings.backgroundColor.opacity(0.8))
                .cornerRadius(8)
            } header: {
                Text("Terminal Colors")
            } footer: {
                Text("Customize message colors for better visibility")
            }

            // Timestamp Settings
            Section {
                Toggle("Show timestamps", isOn: $settings.showTimestamps)

                if settings.showTimestamps {
                    Picker("Timestamp format", selection: $settings.timestampFormat) {
                        Text("HH:mm:ss").tag("HH:mm:ss")
                        Text("HH:mm:ss.SSS").tag("HH:mm:ss.SSS")
                        Text("Relative (e.g., 5s ago)").tag("relative")
                    }
                }
            } header: {
                Text("Timestamps")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
