//
//  AdvancedSettingsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var bluetoothManager: BluetoothManager
    let onExportDebugLog: () -> Void
    let onClearDiagnostics: () -> Void

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
                    Button("Export Debug Log") {
                        onExportDebugLog()
                    }

                    Button("Clear BLE Diagnostics Buffer") {
                        onClearDiagnostics()
                    }
                    .foregroundColor(.orange)

                    Button("Clear All User Defaults") {
                        clearUserDefaults()
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Debug Actions")
                } footer: {
                    Text("⚠️ Debug actions are only visible when Debug Mode is enabled")
                }
            }

            if settings.debugMode {
                Section {
                    HStack {
                        Text("BLE Event Count")
                        Spacer()
                        Text("\\(bluetoothManager.bleEventLog.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Raw Packet Count")
                        Spacer()
                        Text("\\(bluetoothManager.rawPackets.count)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Runtime Diagnostics")
                } footer: {
                    Text("Event and packet buffers are in-memory and reset when the app restarts.")
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
