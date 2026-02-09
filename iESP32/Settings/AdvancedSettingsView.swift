//
//  AdvancedSettingsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            // Developer Options
            Section {
                Toggle("Show raw data packets", isOn: $settings.showRawDataPackets)
                Toggle("Log all BLE events", isOn: $settings.logAllBLEEvents)
                Toggle("Debug mode", isOn: $settings.debugMode)
                Toggle("Show message byte count", isOn: $settings.showMessageByteCount)
            } header: {
                Text("Developer Options")
            } footer: {
                Text("These options are useful for debugging and development. Enabling them may impact app performance.")
            }

            // Diagnostic Information
            Section {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build Number")
                    Spacer()
                    Text("1")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("iOS Version")
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Device Model")
                    Spacer()
                    Text(UIDevice.current.model)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }

            // Debug Actions
            if settings.debugMode {
                Section {
                    Button("Clear All User Defaults") {
                        clearUserDefaults()
                    }
                    .foregroundColor(.orange)

                    Button("Export Debug Log") {
                        // TODO: Implement debug log export
                    }
                } header: {
                    Text("Debug Actions")
                } footer: {
                    Text("⚠️ Debug actions are only visible when Debug Mode is enabled")
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
    }
}
