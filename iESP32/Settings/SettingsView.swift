//
//  SettingsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false

    var body: some View {
        NavigationView {
            Form {
                // Appearance Section
                Section {
                    NavigationLink(destination: AppearanceSettingsView(settings: settings)) {
                        Label("Appearance", systemImage: "paintbrush.fill")
                    }
                } header: {
                    Text("Interface")
                }

                // Terminal Behavior Section
                Section {
                    Toggle("Auto-scroll", isOn: $settings.autoScroll)
                    Toggle("Clear on connect", isOn: $settings.clearOnConnect)
                    Toggle("Text wrapping", isOn: $settings.textWrapping)
                    Toggle("Show line numbers", isOn: $settings.showLineNumbers)

                    Picker("Message buffer size", selection: $settings.messageBufferSize) {
                        Text("100 messages").tag(100)
                        Text("500 messages").tag(500)
                        Text("1000 messages").tag(1000)
                        Text("5000 messages").tag(5000)
                        Text("Unlimited").tag(-1)
                    }
                } header: {
                    Text("Terminal Behavior")
                } footer: {
                    Text("Buffer size limits the number of messages stored in history. Unlimited may impact performance.")
                }

                // Connection Settings Section
                Section {
                    NavigationLink(destination: ConnectionSettingsView(settings: settings)) {
                        Label("Connection Settings", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } header: {
                    Text("Connection")
                }

                // Notifications & Sounds Section
                Section {
                    Toggle("Connection sound", isOn: $settings.connectionSound)
                    Toggle("Disconnection alert", isOn: $settings.disconnectionAlert)
                    Toggle("Message received sound", isOn: $settings.messageReceivedSound)
                    Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
                } header: {
                    Text("Notifications & Sounds")
                }

                // Data Management Section
                Section {
                    Picker("Export format", selection: $settings.exportFormat) {
                        Text("Text").tag("text")
                        Text("JSON").tag("json")
                        Text("CSV").tag("csv")
                    }

                    Picker("Command history size", selection: $settings.commandHistorySize) {
                        Text("25 commands").tag(25)
                        Text("50 commands").tag(50)
                        Text("100 commands").tag(100)
                        Text("200 commands").tag(200)
                    }

                    Toggle("Auto-export on disconnect", isOn: $settings.autoExportOnDisconnect)
                } header: {
                    Text("Data Management")
                }

                // Developer Options Section
                Section {
                    NavigationLink(destination: AdvancedSettingsView(settings: settings)) {
                        Label("Advanced & Developer", systemImage: "wrench.and.screwdriver.fill")
                    }
                } header: {
                    Text("Advanced")
                }

                // Reset Section
                Section {
                    Button(role: .destructive, action: {
                        showResetAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Reset to Defaults")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("iESP32 v1.0 • Built with ❤️ for ESP32 enthusiasts")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset All Settings?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                }
            } message: {
                Text("This will restore all settings to their default values. This action cannot be undone.")
            }
        }
    }
}
