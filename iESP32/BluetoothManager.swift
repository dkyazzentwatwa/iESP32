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
    @Published var connectionState: ConnectionState = .disconnected {
        didSet {
            onConnectionStateChanged?(connectionState)
        }
    }
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var deviceRSSI: [UUID: Int] = [:] // Store RSSI for discovered devices
    @Published var bleEventLog: [BLEEvent] = []
    @Published var rawPackets: [RawPacket] = []
    @Published var isTransportReady = false

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
    private var txWriteType: CBCharacteristicWriteType = .withResponse
    private var queuedWritesWithoutResponse: [PendingWrite] = []
    private let maxQueuedWritesWithoutResponse = 128
    private var connectionTimer: Timer?
    private var rssiTimer: Timer?
    private var durationTimer: Timer?
    private var dataRateTimer: Timer?
    private var lastDataRateCheck: Date?
    private var bytesInLastSecond: Int = 0

    // Message buffering for incoming data
    private var receiveBuffer: String = ""
    private var partialLineFlushWorkItem: DispatchWorkItem?

    // Nordic UART Service UUIDs (nonisolated - these are constants)
    nonisolated(unsafe) private let nordicUARTServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) private let txCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // Callback for received messages
    var onMessageReceived: ((String) -> Void)?
    var onMessageDeliveryStatusChanged: ((UUID, MessageDeliveryStatus) -> Void)?
    var onBluetoothPoweredOn: (() -> Void)?
    var onConnectionStateChanged: ((ConnectionState) -> Void)?

    // Settings Manager
    weak var settingsManager: SettingsManager?

    // Track manual disconnect to prevent auto-reconnect
    private var wasManualDisconnect = false
    private var pendingSentMessageIDs: [UUID] = []
    private let maxStoredEvents = 1000
    private let maxStoredPackets = 1000

    private struct PendingWrite {
        let data: Data
        let messageID: UUID?
    }

    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            showAlert(message: "Bluetooth is not powered on. Please enable Bluetooth in Settings.")
            appendEvent(level: "warn", "Scan requested while bluetooth is not powered on")
            return
        }

        discoveredDevices.removeAll()
        deviceRSSI.removeAll() // Clear RSSI values
        isScanning = true
        connectionState = .scanning
        appendEvent("Started scanning for peripherals")
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
        appendEvent("Stopped scanning")
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        connectedDevice = peripheral
        peripheral.delegate = self
        appendEvent("Connecting to \(peripheral.name ?? "Unknown")")
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
        appendEvent("Manual disconnect requested for \(peripheral.name ?? "Unknown")")
        centralManager.cancelPeripheralConnection(peripheral)
        resetConnection()
    }

    @discardableResult
    func sendMessage(_ message: String, messageID: UUID? = nil) -> Bool {
        guard isTransportReady else {
            showAlert(message: "Connection is not ready yet. Please wait a moment and try again.")
            appendEvent(level: "warn", "TX attempted before transport ready")
            if let messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
            return false
        }

        guard let txCharacteristic = txCharacteristic,
              let connectedDevice = connectedDevice else {
            showAlert(message: "Cannot send message. Not connected or invalid message.")
            appendEvent(level: "error", "TX failed: missing connection or characteristic")
            if let messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
            return false
        }

        // Add newline terminator for ESP32 UART commands
        let messageWithNewline = message + "\n"
        guard let data = messageWithNewline.data(using: .utf8) else {
            showAlert(message: "Cannot encode message.")
            appendEvent(level: "error", "TX failed: utf8 encoding error")
            if let messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
            return false
        }

        switch txWriteType {
        case .withResponse:
            if let messageID {
                pendingSentMessageIDs.append(messageID)
            }
            connectedDevice.writeValue(data, for: txCharacteristic, type: .withResponse)
            recordSuccessfulWrite(data: data, eventSuffix: "")
            return true

        case .withoutResponse:
            return enqueueOrSendWithoutResponse(
                PendingWrite(data: data, messageID: messageID),
                peripheral: connectedDevice,
                characteristic: txCharacteristic
            )

        @unknown default:
            if let messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
            appendEvent(level: "error", "TX failed: unsupported write type")
            return false
        }
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
        appendEvent(level: "error", "Connection timeout")
        resetConnection()
    }

    private func resetConnection() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        stopMonitoring()
        txCharacteristic = nil
        rxCharacteristic = nil
        isTransportReady = false
        connectedDevice = nil
        connectionState = .disconnected
        resetStats()
        partialLineFlushWorkItem?.cancel()
        partialLineFlushWorkItem = nil
        for messageID in pendingSentMessageIDs {
            onMessageDeliveryStatusChanged?(messageID, .failed)
        }
        pendingSentMessageIDs.removeAll()
        for pendingWrite in queuedWritesWithoutResponse {
            if let messageID = pendingWrite.messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
        }
        queuedWritesWithoutResponse.removeAll()

        // Clear receive buffer
        receiveBuffer = ""
    }

    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }

    private func appendEvent(level: String = "info", _ message: String) {
        let shouldStore = settingsManager?.logAllBLEEvents == true || settingsManager?.debugMode == true
        guard shouldStore else { return }

        bleEventLog.append(BLEEvent(level: level, message: message))
        if bleEventLog.count > maxStoredEvents {
            bleEventLog.removeFirst(bleEventLog.count - maxStoredEvents)
        }
    }

    private func appendRawPacket(direction: RawPacket.Direction, payload: Data) {
        guard settingsManager?.showRawDataPackets == true else { return }

        rawPackets.append(RawPacket(direction: direction, payload: payload))
        if rawPackets.count > maxStoredPackets {
            rawPackets.removeFirst(rawPackets.count - maxStoredPackets)
        }
    }

    private func recordSuccessfulWrite(data: Data, eventSuffix: String) {
        appendEvent("TX \(data.count) bytes\(eventSuffix)")
        appendRawPacket(direction: .tx, payload: data)
        bytesSent += data.count
        messagesSent += 1
        bytesInLastSecond += data.count
    }

    private func enqueueOrSendWithoutResponse(
        _ pendingWrite: PendingWrite,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) -> Bool {
        if queuedWritesWithoutResponse.isEmpty, peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(pendingWrite.data, for: characteristic, type: .withoutResponse)
            recordSuccessfulWrite(data: pendingWrite.data, eventSuffix: " (withoutResponse)")
            if let messageID = pendingWrite.messageID {
                onMessageDeliveryStatusChanged?(messageID, .delivered)
            }
            return true
        }

        guard queuedWritesWithoutResponse.count < maxQueuedWritesWithoutResponse else {
            appendEvent(level: "error", "TX queue full for withoutResponse writes")
            if let messageID = pendingWrite.messageID {
                onMessageDeliveryStatusChanged?(messageID, .failed)
            }
            showAlert(message: "Send queue is full. Please wait and try again.")
            return false
        }

        queuedWritesWithoutResponse.append(pendingWrite)
        appendEvent("TX queued (\(queuedWritesWithoutResponse.count) pending)")
        drainWithoutResponseQueue(peripheral: peripheral, characteristic: characteristic)
        return true
    }

    private func drainWithoutResponseQueue(peripheral: CBPeripheral? = nil, characteristic: CBCharacteristic? = nil) {
        guard txWriteType == .withoutResponse else { return }
        guard let targetPeripheral = peripheral ?? connectedDevice,
              let targetCharacteristic = characteristic ?? txCharacteristic else {
            return
        }

        while targetPeripheral.canSendWriteWithoutResponse && !queuedWritesWithoutResponse.isEmpty {
            let pendingWrite = queuedWritesWithoutResponse.removeFirst()
            targetPeripheral.writeValue(pendingWrite.data, for: targetCharacteristic, type: .withoutResponse)
            recordSuccessfulWrite(data: pendingWrite.data, eventSuffix: " (withoutResponse)")
            if let messageID = pendingWrite.messageID {
                onMessageDeliveryStatusChanged?(messageID, .delivered)
            }
        }
    }

    func clearDiagnostics() {
        bleEventLog.removeAll()
        rawPackets.removeAll()
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
            appendEvent("Bluetooth state updated: \(central.state.rawValue)")

            switch central.state {
            case .poweredOff:
                showAlert(message: "Bluetooth is turned off. Please enable it in Settings.")
                resetConnection()
            case .unauthorized:
                showAlert(message: "Bluetooth access is not authorized. Please grant permission in Settings.")
            case .unsupported:
                showAlert(message: "Bluetooth Low Energy is not supported on this device.")
            case .poweredOn:
                onBluetoothPoweredOn?()
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
                appendEvent("Discovered \(peripheral.name ?? "Unknown") RSSI \(RSSI.intValue)")
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
            isTransportReady = false
            startMonitoring()
            peripheral.discoverServices([nordicUARTServiceUUID])
            appendEvent("Connected to \(peripheral.name ?? "Unknown")")

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
            appendEvent(level: "error", "Failed to connect: \(errorMessage)")
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
                    appendEvent(level: "warn", "Disconnected with error: \(error.localizedDescription)")
                } else {
                    showAlert(message: "Disconnected from \(peripheral.name ?? "device")")
                    appendEvent("Disconnected from \(peripheral.name ?? "Unknown")")
                }
            }

            // Attempt auto-reconnect if enabled and not a manual disconnect
            let shouldAutoReconnect = settingsManager?.autoReconnect ?? false
            let shouldReconnect = shouldAutoReconnect && !wasManualDisconnect

            // Always emit a disconnected transition so session close/export can run.
            resetConnection()

            if shouldReconnect {
                // Wait 2 seconds before attempting reconnect
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                appendEvent("Auto-reconnect attempt")
                connect(to: peripheral)
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
                appendEvent(level: "error", "Service discovery error: \(error.localizedDescription)")
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
                appendEvent(level: "error", "Characteristic discovery error: \(error.localizedDescription)")
                return
            }

            guard let characteristics = service.characteristics else { return }

            var didSetTX = false
            var didSetRX = false

            for characteristic in characteristics {
                switch characteristic.uuid {
                case txCharacteristicUUID:
                    txCharacteristic = characteristic
                    if characteristic.properties.contains(.writeWithoutResponse) {
                        txWriteType = .withoutResponse
                    } else if characteristic.properties.contains(.write) {
                        txWriteType = .withResponse
                    } else {
                        showAlert(message: "TX characteristic does not support writing.")
                        appendEvent(level: "error", "TX characteristic missing write properties")
                    }
                    didSetTX = true
                    appendEvent("TX characteristic ready")
                case rxCharacteristicUUID:
                    rxCharacteristic = characteristic
                    if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    } else {
                        showAlert(message: "RX characteristic does not support notifications.")
                        appendEvent(level: "error", "RX characteristic missing notify/indicate")
                    }
                    didSetRX = true
                    appendEvent("RX characteristic ready with notifications enabled")
                default:
                    break
                }
            }

            if !didSetTX || !didSetRX {
                appendEvent(level: "warn", "UART characteristics incomplete (tx: \(didSetTX), rx: \(didSetRX))")
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
        appendRawPacket(direction: .rx, payload: data)

        // DEBUG: Log raw bytes (enabled via settings)
        if settingsManager?.debugMode == true {
            let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("📦 BLE RX [\(data.count) bytes]: \(hexString)")
        }

        // Simplified approach: Try UTF-8 decode, filter out invalid bytes if it fails
        if let str = String(data: data, encoding: .utf8) {
            // Valid UTF-8 - use it directly
            if settingsManager?.debugMode == true {
                print("✅ UTF-8: \"\(str.debugDescription)\"")
            }
            receiveBuffer += str
        } else {
            // Contains invalid UTF-8 - filter out non-printable bytes
            let validBytes = data.filter { byte in
                // Keep printable ASCII (0x20-0x7E) and common control chars
                (byte >= 0x20 && byte <= 0x7E) ||  // Printable ASCII
                byte == 0x0A ||  // LF
                byte == 0x0D ||  // CR
                byte == 0x09     // Tab
            }

            if let str = String(data: Data(validBytes), encoding: .utf8) {
                if settingsManager?.debugMode == true {
                    print("⚠️ FILTERED (\(data.count - validBytes.count) invalid bytes): \"\(str.debugDescription)\"")
                }
                receiveBuffer += str
            } else {
                // Still can't decode - show as hex
                let hexStr = data.map { String(format: "<%02X>", $0) }.joined()
                if settingsManager?.debugMode == true {
                    print("❌ BINARY: \(hexStr)")
                }
                receiveBuffer += hexStr
            }
        }

        // Process complete lines
        processCompleteLines()
        schedulePartialLineFlush()
    }

    private func processCompleteLines() {
        // Called from main thread via handleReceivedData
        var firstMessage = true

        // Process while buffer contains any newline character
        while let separatorIndex = receiveBuffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            // Extract line content (everything before the separator)
            let line = String(receiveBuffer[..<separatorIndex])

            // Calculate how many characters to remove (line + separator)
            var removeCount = receiveBuffer.distance(from: receiveBuffer.startIndex, to: separatorIndex) + 1

            // Check for \r\n pair and remove both
            let afterSeparator = receiveBuffer.index(after: separatorIndex)
            if receiveBuffer[separatorIndex] == "\r" &&
               afterSeparator < receiveBuffer.endIndex &&
               receiveBuffer[afterSeparator] == "\n" {
                removeCount += 1
            }

            // Remove processed characters from buffer
            receiveBuffer.removeFirst(removeCount)

            // Skip empty lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
    }

    private func schedulePartialLineFlush() {
        partialLineFlushWorkItem?.cancel()
        let flushTask = DispatchWorkItem { [weak self] in
            self?.flushPartialBufferIfNeeded()
        }
        partialLineFlushWorkItem = flushTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: flushTask)
    }

    private func flushPartialBufferIfNeeded() {
        guard !receiveBuffer.isEmpty else { return }

        let buffered = receiveBuffer
        receiveBuffer = ""
        partialLineFlushWorkItem = nil

        messagesReceived += 1
        onMessageReceived?(buffered)
        playMessageReceivedSound()
        appendEvent("Flushed non-terminated RX chunk (\(buffered.utf8.count) bytes)")
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            let sentMessageID = pendingSentMessageIDs.isEmpty ? nil : pendingSentMessageIDs.removeFirst()
            if let error = error {
                showAlert(message: "Failed to send message: \(error.localizedDescription)")
                appendEvent(level: "error", "TX write error: \(error.localizedDescription)")
                if let sentMessageID {
                    onMessageDeliveryStatusChanged?(sentMessageID, .failed)
                }
                return
            }

            appendEvent("TX write acknowledged")
            if let sentMessageID {
                onMessageDeliveryStatusChanged?(sentMessageID, .delivered)
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

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == rxCharacteristicUUID else { return }

            if let error {
                isTransportReady = false
                showAlert(message: "Failed to enable RX notifications: \(error.localizedDescription)")
                appendEvent(level: "error", "RX notify enable failed: \(error.localizedDescription)")
                return
            }

            isTransportReady = characteristic.isNotifying && txCharacteristic != nil
            appendEvent("RX notifications active: \(characteristic.isNotifying)")
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard peripheral.identifier == connectedDevice?.identifier else { return }
            drainWithoutResponseQueue(peripheral: peripheral, characteristic: txCharacteristic)
        }
    }
}
