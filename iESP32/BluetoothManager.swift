//
//  BluetoothManager.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation
import CoreBluetooth
import SwiftUI
import Combine
import AVFoundation

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case scanning
}

enum ConnectionQuality {
    case excellent // RSSI > -60
    case good      // RSSI > -70
    case fair      // RSSI > -80
    case poor      // RSSI <= -80
    case unknown

    var displayText: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

struct RSSIReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Int
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var deviceRSSI: [UUID: Int] = [:] // Store RSSI for discovered devices

    // MARK: - Stats Properties
    @Published var rssiValue: Int = 0
    @Published var rssiHistory: [RSSIReading] = []
    @Published var bytesSent: Int = 0
    @Published var bytesReceived: Int = 0
    @Published var messagesSent: Int = 0
    @Published var messagesReceived: Int = 0
    @Published var connectionDuration: TimeInterval = 0
    @Published var dataRate: Double = 0 // bytes per second
    @Published var connectionQuality: ConnectionQuality = .unknown
    @Published var connectionStartTime: Date?
    @Published var peakDataRate: Double = 0

    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var connectionTimer: Timer?
    private var rssiTimer: Timer?
    private var durationTimer: Timer?
    private var dataRateTimer: Timer?
    private var lastDataRateCheck: Date?
    private var bytesInLastSecond: Int = 0

    // Message buffering for incoming data
    private var receiveBuffer = Data()

    // Nordic UART Service UUIDs (nonisolated - these are constants)
    nonisolated(unsafe) private let nordicUARTServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) private let txCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // Callback for received messages
    var onMessageReceived: ((String) -> Void)?

    // Settings Manager
    weak var settingsManager: SettingsManager?

    // Track manual disconnect to prevent auto-reconnect
    private var wasManualDisconnect = false

    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            showAlert(message: "Bluetooth is not powered on. Please enable Bluetooth in Settings.")
            return
        }

        discoveredDevices.removeAll()
        deviceRSSI.removeAll() // Clear RSSI values
        isScanning = true
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [nordicUARTServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        // Auto-stop scanning (use setting or default to 10 seconds)
        let scanDuration = settingsManager?.scanDuration ?? 10
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(scanDuration)) { [weak self] in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        connectedDevice = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        // Connection timeout (use setting or default to 10 seconds)
        let timeout = Double(settingsManager?.connectionTimeout ?? 10)
        connectionTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConnectionTimeout()
            }
        }
    }

    func disconnect() {
        guard let peripheral = connectedDevice else { return }
        wasManualDisconnect = true
        centralManager.cancelPeripheralConnection(peripheral)
        resetConnection()
    }

    func sendMessage(_ message: String) {
        guard let txCharacteristic = txCharacteristic,
              let connectedDevice = connectedDevice else {
            showAlert(message: "Cannot send message. Not connected or invalid message.")
            return
        }

        // Add newline terminator for ESP32 UART commands
        let messageWithNewline = message + "\n"
        guard let data = messageWithNewline.data(using: .utf8) else {
            showAlert(message: "Cannot encode message.")
            return
        }

        connectedDevice.writeValue(data, for: txCharacteristic, type: .withResponse)

        // Update stats
        bytesSent += data.count
        messagesSent += 1
        bytesInLastSecond += data.count
    }

    // MARK: - Stats Methods
    func startMonitoring() {
        // Start RSSI monitoring (every 1 second)
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRSSI()
            }
        }

        // Start duration timer (every 1 second)
        connectionStartTime = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }

        // Start data rate calculation (every 1 second)
        lastDataRateCheck = Date()
        dataRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.calculateDataRate()
            }
        }
    }

    func stopMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        dataRateTimer?.invalidate()
        dataRateTimer = nil
    }

    private func updateRSSI() {
        guard let peripheral = connectedDevice else { return }
        peripheral.readRSSI()
    }

    private func updateDuration() {
        guard let startTime = connectionStartTime else { return }
        connectionDuration = Date().timeIntervalSince(startTime)
    }

    private func calculateDataRate() {
        guard let lastCheck = lastDataRateCheck else { return }

        let elapsed = Date().timeIntervalSince(lastCheck)
        if elapsed > 0 {
            dataRate = Double(bytesInLastSecond) / elapsed
            if dataRate > peakDataRate {
                peakDataRate = dataRate
            }
        }

        // Reset for next calculation
        bytesInLastSecond = 0
        lastDataRateCheck = Date()
    }

    private func updateConnectionQuality(rssi: Int) {
        if rssi > -60 {
            connectionQuality = .excellent
        } else if rssi > -70 {
            connectionQuality = .good
        } else if rssi > -80 {
            connectionQuality = .fair
        } else {
            connectionQuality = .poor
        }
    }

    func resetStats() {
        bytesSent = 0
        bytesReceived = 0
        messagesSent = 0
        messagesReceived = 0
        connectionDuration = 0
        dataRate = 0
        peakDataRate = 0
        rssiValue = 0
        rssiHistory.removeAll()
        connectionQuality = .unknown
        connectionStartTime = nil
        bytesInLastSecond = 0
    }

    // MARK: - Private Methods
    private func handleConnectionTimeout() {
        guard connectionState == .connecting else { return }

        if let peripheral = connectedDevice {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        showAlert(message: "Connection failed. Device may be out of range.")
        resetConnection()
    }

    private func resetConnection() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        stopMonitoring()
        resetStats()
        txCharacteristic = nil
        rxCharacteristic = nil
        connectedDevice = nil
        connectionState = .disconnected

        // Clear receive buffer
        receiveBuffer = Data()
    }

    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }

    // MARK: - Sound & Haptic Feedback
    private func playConnectionSound() {
        guard settingsManager?.connectionSound == true else { return }
        AudioServicesPlaySystemSound(1057) // System connect sound
    }

    private func playMessageReceivedSound() {
        guard settingsManager?.messageReceivedSound == true else { return }
        AudioServicesPlaySystemSound(1003) // System received sound
    }

    private func triggerHaptic() {
        guard settingsManager?.hapticFeedback == true else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = central.state

            switch central.state {
            case .poweredOff:
                showAlert(message: "Bluetooth is turned off. Please enable it in Settings.")
                resetConnection()
            case .unauthorized:
                showAlert(message: "Bluetooth access is not authorized. Please grant permission in Settings.")
            case .unsupported:
                showAlert(message: "Bluetooth Low Energy is not supported on this device.")
            case .poweredOn:
                break
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
            // Store RSSI value for this device
            deviceRSSI[peripheral.identifier] = RSSI.intValue
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionTimer?.invalidate()
            connectionTimer = nil
            connectionState = .connected
            startMonitoring()
            peripheral.discoverServices([nordicUARTServiceUUID])

            // Save last connected device if enabled
            if settingsManager?.rememberLastDevice == true {
                settingsManager?.lastDeviceUUID = peripheral.identifier.uuidString
                settingsManager?.lastDeviceName = peripheral.name ?? "Unknown"
            }

            // Play connection sound if enabled
            playConnectionSound()

            // Trigger haptic feedback if enabled
            triggerHaptic()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            showAlert(message: "Failed to connect: \(errorMessage)")
            resetConnection()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            // Show alert based on disconnection alert setting
            let shouldShowAlert = settingsManager?.disconnectionAlert ?? true
            if shouldShowAlert {
                if let error = error {
                    showAlert(message: "Connection lost: \(error.localizedDescription)")
                } else {
                    showAlert(message: "Disconnected from \(peripheral.name ?? "device")")
                }
            }

            // Attempt auto-reconnect if enabled and not a manual disconnect
            let shouldAutoReconnect = settingsManager?.autoReconnect ?? false
            if shouldAutoReconnect && !wasManualDisconnect {
                // Wait 2 seconds before attempting reconnect
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                connect(to: peripheral)
            } else {
                resetConnection()
            }

            // Reset manual disconnect flag
            wasManualDisconnect = false
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                showAlert(message: "Error discovering services: \(error.localizedDescription)")
                return
            }

            guard let services = peripheral.services else { return }

            for service in services where service.uuid == nordicUARTServiceUUID {
                peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                showAlert(message: "Error discovering characteristics: \(error.localizedDescription)")
                return
            }

            guard let characteristics = service.characteristics else { return }

            for characteristic in characteristics {
                switch characteristic.uuid {
                case txCharacteristicUUID:
                    txCharacteristic = characteristic
                case rxCharacteristicUUID:
                    rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // CRITICAL: Handle errors synchronously
        if let error = error {
            Task { @MainActor in
                showAlert(message: "Error receiving data: \(error.localizedDescription)")
            }
            return
        }

        // CRITICAL: Check UUID and capture data IMMEDIATELY (synchronously)
        // The BLE stack may update characteristic.value with the next packet
        // before any async Task code runs - this causes data corruption!
        guard characteristic.uuid == rxCharacteristicUUID,
              let data = characteristic.value, !data.isEmpty else {
            return
        }

        // Make a copy of the bytes NOW while we still have the correct data
        let capturedBytes = Data(data)

        // CRITICAL: Use DispatchQueue.main.async instead of Task { @MainActor }
        // Task doesn't guarantee FIFO ordering - packets can be processed out of order!
        // DispatchQueue.main.async DOES guarantee FIFO ordering
        DispatchQueue.main.async { [weak self] in
            self?.handleReceivedData(capturedBytes)
        }
    }

    private func handleReceivedData(_ data: Data) {
        // Called from DispatchQueue.main.async, guaranteed to be on main thread
        // Update stats
        bytesReceived += data.count
        bytesInLastSecond += data.count

        // DEBUG: Log raw bytes (enabled via settings)
        if settingsManager?.debugMode == true {
            let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("📦 BLE RX [\(data.count) bytes]: \(hexString)")
        }

        // Append to buffer
        receiveBuffer.append(data)

        // Process complete lines
        processCompleteLines()
    }

    private func processCompleteLines() {
        // Called from main thread via handleReceivedData
        var firstMessage = true

        // Process while buffer contains any newline character
        // 0x0A is \n, 0x0D is \r
        while let separatorIndex = receiveBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            // Extract line content (everything before the separator)
            let lineData = receiveBuffer.subdata(in: 0..<separatorIndex)

            // Calculate how many bytes to remove (line + separator)
            var removeCount = separatorIndex + 1

            // Check for \r\n pair and remove both
            if receiveBuffer[separatorIndex] == 0x0D &&
               separatorIndex + 1 < receiveBuffer.count &&
               receiveBuffer[separatorIndex + 1] == 0x0A {
                removeCount += 1
            }

            // Remove processed bytes from buffer
            receiveBuffer.removeSubrange(0..<removeCount)

            // Decode line
            let decodedLine: String
            if let str = String(data: lineData, encoding: .utf8) {
                if settingsManager?.debugMode == true {
                    print("✅ Decoded Line: \"\(str)\"")
                }
                decodedLine = str
            } else {
                // Fallback for invalid UTF-8 - filter out non-printable bytes
                let validBytes = lineData.filter { byte in
                    // Keep printable ASCII (0x20-0x7E) and common control chars
                    (byte >= 0x20 && byte <= 0x7E) ||
                    byte == 0x09 // Tab
                }

                if let str = String(data: Data(validBytes), encoding: .utf8) {
                    if settingsManager?.debugMode == true {
                        print("⚠️ Decoded Filtered Line: \"\(str)\"")
                    }
                    decodedLine = str
                } else {
                    // Still can't decode - show as hex
                    decodedLine = lineData.map { String(format: "<%02X>", $0) }.joined()
                    if settingsManager?.debugMode == true {
                        print("❌ Binary Line: \(decodedLine)")
                    }
                }
            }

            // Skip empty lines
            let trimmed = decodedLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Send to terminal
            messagesReceived += 1
            onMessageReceived?(trimmed)

            // Play sound for first message in this batch
            if firstMessage {
                playMessageReceivedSound()
                firstMessage = false
            }
        }

        // Safety: If buffer grows too large without newlines, clear it to prevent memory issues
        if receiveBuffer.count > 1024 * 10 { // 10KB limit for a single line
             receiveBuffer.removeAll()
             if settingsManager?.debugMode == true {
                 print("🚨 Buffer cleared due to size limit (no newlines found)")
             }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                showAlert(message: "Failed to send message: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }

            rssiValue = RSSI.intValue
            updateConnectionQuality(rssi: rssiValue)

            // Add to history (keep last 60 readings)
            let reading = RSSIReading(timestamp: Date(), value: rssiValue)
            rssiHistory.append(reading)
            if rssiHistory.count > 60 {
                rssiHistory.removeFirst()
            }
        }
    }
}
