//
//  ConnectionStatsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI
import Charts
import CoreBluetooth

struct ConnectionStatsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Section
                    connectionStatusSection

                    // Signal Strength Section
                    if bluetoothManager.connectionState == .connected {
                        signalStrengthSection
                        rssiChartSection
                    }

                    // Data Transfer Statistics
                    dataTransferSection

                    // Performance Metrics
                    performanceMetricsSection
                }
                .padding()
            }
            .navigationTitle("Connection Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Connection Status Section
    private var connectionStatusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: connectionStatusIcon)
                        .font(.title2)
                        .foregroundColor(connectionStatusColor)

                    VStack(alignment: .leading) {
                        Text(connectionStatusText)
                            .font(.headline)
                        if let device = bluetoothManager.connectedDevice {
                            Text(device.name ?? "Unknown Device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Connection Quality Badge
                    if bluetoothManager.connectionState == .connected {
                        VStack(alignment: .trailing) {
                            Text(bluetoothManager.connectionQuality.displayText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(bluetoothManager.connectionQuality.color)

                            HStack(spacing: 2) {
                                ForEach(0..<4) { index in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(signalBarColor(for: index))
                                        .frame(width: 6, height: CGFloat(8 + (index * 4)))
                                }
                            }
                        }
                    }
                }

                if bluetoothManager.connectionState == .connected {
                    Divider()

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatDuration(bluetoothManager.connectionDuration))
                                .font(.system(.body, design: .monospaced))
                        }

                        Spacer()

                        if let device = bluetoothManager.connectedDevice {
                            VStack(alignment: .trailing) {
                                Text("Device UUID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(device.identifier.uuidString.prefix(8) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .padding()
        } label: {
            Label("Connection Status", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    // MARK: - Signal Strength Section
    private var signalStrengthSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("RSSI")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(bluetoothManager.rssiValue) dBm")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Signal Quality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(signalQualityPercentage)%")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(bluetoothManager.connectionQuality.color)
                    }
                }

                // Signal Strength Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(signalQualityPercentage) / 100.0)
                    }
                }
                .frame(height: 20)
            }
            .padding()
        } label: {
            Label("Signal Strength", systemImage: "waveform")
        }
    }

    // MARK: - RSSI Chart Section
    private var rssiChartSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 60 Seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !bluetoothManager.rssiHistory.isEmpty {
                    Chart(bluetoothManager.rssiHistory) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("RSSI", reading.value)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: -100...(-30))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 15)) { _ in
                            AxisValueLabel(format: .dateTime.minute().second())
                        }
                    }
                    .frame(height: 150)
                } else {
                    Text("No signal data yet")
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        } label: {
            Label("Signal History", systemImage: "chart.xyaxis.line")
        }
    }

    // MARK: - Data Transfer Section
    private var dataTransferSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                // Bytes Sent
                statsRow(
                    icon: "arrow.up.circle.fill",
                    label: "Bytes Sent",
                    value: formatBytes(bluetoothManager.bytesSent),
                    color: .blue
                )

                Divider()

                // Bytes Received
                statsRow(
                    icon: "arrow.down.circle.fill",
                    label: "Bytes Received",
                    value: formatBytes(bluetoothManager.bytesReceived),
                    color: .green
                )

                Divider()

                // Total Bytes
                statsRow(
                    icon: "arrow.left.arrow.right.circle.fill",
                    label: "Total Bytes",
                    value: formatBytes(bluetoothManager.bytesSent + bluetoothManager.bytesReceived),
                    color: .purple
                )

                Divider()

                HStack {
                    // Messages Sent
                    VStack(alignment: .leading) {
                        Text("Messages Sent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(bluetoothManager.messagesSent)")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    // Messages Received
                    VStack(alignment: .trailing) {
                        Text("Messages Received")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(bluetoothManager.messagesReceived)")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
        } label: {
            Label("Data Transfer", systemImage: "arrow.left.arrow.right")
        }
    }

    // MARK: - Performance Metrics Section
    private var performanceMetricsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current Data Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(formatDataRate(bluetoothManager.dataRate))")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Peak Data Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(formatDataRate(bluetoothManager.peakDataRate))")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
        } label: {
            Label("Performance", systemImage: "speedometer")
        }
    }

    // MARK: - Helper Views
    private func statsRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
            }

            Spacer()
        }
    }

    // MARK: - Helper Properties
    private var connectionStatusIcon: String {
        switch bluetoothManager.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .scanning: return "magnifyingglass"
        case .disconnected: return "xmark.circle.fill"
        }
    }

    private var connectionStatusColor: Color {
        switch bluetoothManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .scanning: return .blue
        case .disconnected: return .red
        }
    }

    private var connectionStatusText: String {
        switch bluetoothManager.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .scanning: return "Scanning"
        case .disconnected: return "Disconnected"
        }
    }

    private var signalQualityPercentage: Int {
        // Convert RSSI (-100 to -30) to percentage (0 to 100)
        let rssi = bluetoothManager.rssiValue
        let percentage = min(max((rssi + 100) * 100 / 70, 0), 100)
        return percentage
    }

    private func signalBarColor(for index: Int) -> Color {
        let threshold = signalQualityPercentage / 25
        return index < threshold ? bluetoothManager.connectionQuality.color : Color.gray.opacity(0.3)
    }

    // MARK: - Helper Functions
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.2f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    private func formatDataRate(_ rate: Double) -> String {
        if rate < 1024 {
            return String(format: "%.0f B/s", rate)
        } else if rate < 1024 * 1024 {
            return String(format: "%.2f KB/s", rate / 1024.0)
        } else {
            return String(format: "%.2f MB/s", rate / (1024.0 * 1024.0))
        }
    }
}
