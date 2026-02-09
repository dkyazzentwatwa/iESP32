//
//  DevicePickerView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI
import CoreBluetooth

struct DevicePickerView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if bluetoothManager.discoveredDevices.isEmpty {
                    VStack(spacing: 20) {
                        if bluetoothManager.isScanning {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Scanning for ESP32 devices...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No ESP32 devices found.")
                                .font(.headline)
                            Text("Make sure your device is powered on and nearby.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(bluetoothManager.discoveredDevices, id: \.identifier) { peripheral in
                        Button(action: {
                            bluetoothManager.connect(to: peripheral)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peripheral.name ?? "Unknown Device")
                                        .font(.headline)

                                    HStack(spacing: 8) {
                                        Text(peripheral.identifier.uuidString)
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        // Show RSSI if enabled in settings
                                        if settings.showRSSIInList,
                                           let rssi = bluetoothManager.deviceRSSI[peripheral.identifier] {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(rssi) dBm")
                                                .font(.caption)
                                                .foregroundColor(rssiColor(rssi))
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        bluetoothManager.stopScanning()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if bluetoothManager.isScanning {
                        ProgressView()
                    }
                }
            }
        }
        .onAppear {
            bluetoothManager.startScanning()
        }
        .onDisappear {
            bluetoothManager.stopScanning()
        }
    }

    // MARK: - Helper Functions
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 {
            return .green
        } else if rssi > -70 {
            return .blue
        } else if rssi > -80 {
            return .orange
        } else {
            return .red
        }
    }
}
