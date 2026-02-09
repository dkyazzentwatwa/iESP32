//
//  ContentView.swift
//  iESP32
//
//  Created by David KyazzeNtwatwa  on 1/27/26.
//

import SwiftUI
import SwiftData
import CoreBluetooth

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalMessage.timestamp, order: .forward) private var messages: [TerminalMessage]
    @Query(filter: #Predicate<MacroCommand> { $0.isFavorite }, sort: \MacroCommand.name) private var favoriteMacros: [MacroCommand]

    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var settings = SettingsManager()
    @State private var messageText = ""
    @State private var showDevicePicker = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var isTextFieldFocused: Bool

    // Search & Filter State
    @State private var showSearch = false
    @State private var showMacros = false
    @State private var searchText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var filterDirection: MessageDirection? = nil
    @State private var filterTimeRange: TimeRange = .allTime
    @State private var showFilters = false
    @State private var currentSearchResult = 0

    init() {
        // Inject settings manager into bluetooth manager
        let bluetooth = BluetoothManager()
        let settingsManager = SettingsManager()
        bluetooth.settingsManager = settingsManager

        _bluetoothManager = StateObject(wrappedValue: bluetooth)
        _settings = StateObject(wrappedValue: settingsManager)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar (conditional)
                if showSearch {
                    SearchBarView(
                        searchText: $searchText,
                        caseSensitive: $caseSensitive,
                        useRegex: $useRegex,
                        showFilters: $showFilters,
                        resultCount: searchResults.count,
                        currentResult: currentSearchResult,
                        onPrevious: navigateToPreviousResult,
                        onNext: navigateToNextResult
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))

                    // Active filters chips
                    if filterDirection != nil || filterTimeRange != .allTime {
                        activeFiltersView
                    }
                }

                // Connection Bar
                connectionBar
                    .padding()
                    .background(Color(uiColor: .systemBackground))

                Divider()

                // Terminal display
                terminalView

                Divider()

                // Favorite Macros Bar
                if !favoriteMacros.isEmpty {
                    favoritesBar
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
                }

                Divider()

                // Input area
                inputArea
                    .padding()
                    .background(Color(uiColor: .systemBackground))
            }
            .background(settings.backgroundColor.opacity(0.95))
            .navigationTitle("iESP32 Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { withAnimation { showSearch.toggle() } }) {
                        Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: generateExportString()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showStats = true }) {
                        Image(systemName: "chart.bar")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .onAppear {
                setupBluetoothCallback()
                loadCommandHistory()
                attemptAutoConnect()
            }
            .sheet(isPresented: $showDevicePicker) {
                DevicePickerView(bluetoothManager: bluetoothManager, settings: settings)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .sheet(isPresented: $showStats) {
                ConnectionStatsView(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: $showFilters) {
                FilterOptionsView(filterDirection: $filterDirection, filterTimeRange: $filterTimeRange)
            }
            .sheet(isPresented: $showMacros) {
                MacroListView(bluetoothManager: bluetoothManager)
            }
            .alert(isPresented: $bluetoothManager.showAlert) {
                Alert(
                    title: Text("Bluetooth"),
                    message: Text(bluetoothManager.alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .preferredColorScheme(themeColorScheme)
        }
    }

    // MARK: - Theme Helper
    private var themeColorScheme: ColorScheme? {
        switch settings.theme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // System default
        }
    }

    // MARK: - Active Filters View
    private var activeFiltersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let direction = filterDirection {
                    FilterChip(text: direction == .sent ? "Sent Only" : "Received Only") {
                        filterDirection = nil
                    }
                }

                if filterTimeRange != .allTime {
                    FilterChip(text: filterTimeRange.displayText) {
                        filterTimeRange = .allTime
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Connection Bar
    private var connectionBar: some View {
        HStack {
            Button(action: handleConnectionButtonTap) {
                HStack {
                    Image(systemName: connectionButtonIcon)
                    Text(connectionButtonText)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(connectionButtonColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(bluetoothManager.bluetoothState != .poweredOn && bluetoothManager.connectionState == .disconnected)

            Spacer()

            if bluetoothManager.connectionState == .connected {
                rssiIndicator
                    .padding(.trailing, 8)
            }

            if bluetoothManager.isScanning {
                ProgressView()
                    .padding(.trailing, 8)
            }
        }
    }

    private var connectionButtonIcon: String {
        switch bluetoothManager.connectionState {
        case .disconnected:
            return "antenna.radiowaves.left.and.right"
        case .scanning:
            return "magnifyingglass"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "link"
        }
    }

    private var connectionButtonText: String {
        switch bluetoothManager.connectionState {
        case .disconnected:
            return "Scan"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .connected:
            if let device = bluetoothManager.connectedDevice {
                return "Disconnect (\(device.name ?? "Unknown"))"
            }
            return "Disconnect"
        }
    }

    private var connectionButtonColor: Color {
        switch bluetoothManager.connectionState {
        case .disconnected, .scanning:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .blue
        }
    }

    private func handleConnectionButtonTap() {
        if bluetoothManager.connectionState == .connected {
            bluetoothManager.disconnect()
        } else if bluetoothManager.connectionState == .disconnected {
            // Clear terminal if setting is enabled
            if settings.clearOnConnect {
                clearTerminal()
            }
            showDevicePicker = true
        }
    }

    // MARK: - Terminal View
    private var terminalView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array((showSearch || filterDirection != nil || filterTimeRange != .allTime ? filteredMessages : displayedMessages).enumerated()), id: \.element.id) { index, message in
                        TerminalMessageView(message: message, settings: settings, lineNumber: index + 1) { content in
                            messageText = content
                            sendMessage()
                        }
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if settings.autoScroll, let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // Apply message buffer size limit
    private var displayedMessages: [TerminalMessage] {
        guard settings.messageBufferSize > 0 else { return messages }
        let count = messages.count
        let bufferSize = settings.messageBufferSize
        return count > bufferSize ? Array(messages.suffix(bufferSize)) : messages
    }

    // MARK: - Input Area
    private var inputArea: some View {
        HStack(spacing: 12) {
            // Command history buttons
            VStack(spacing: 4) {
                Button(action: navigateHistoryUp) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .frame(width: 30, height: 20)
                }
                .disabled(commandHistory.isEmpty)

                Button(action: navigateHistoryDown) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .frame(width: 30, height: 20)
                }
                .disabled(commandHistory.isEmpty || historyIndex == nil)
            }
            .buttonStyle(.bordered)

            // Text field
            TextField("Enter command...", text: $messageText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(messageText.isEmpty || bluetoothManager.connectionState != .connected)

            // Macros button
            Button(action: { showMacros = true }) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.title3)
            }
            .buttonStyle(.bordered)

            // Clear button
            Button(action: clearTerminal) {
                Image(systemName: "trash")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }

    // MARK: - Actions
    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        // Send via Bluetooth
        bluetoothManager.sendMessage(messageText)

        // Save to history
        let message = TerminalMessage(
            content: messageText,
            direction: .sent,
            deviceName: bluetoothManager.connectedDevice?.name
        )
        modelContext.insert(message)

        // Add to command history
        addToCommandHistory(messageText)

        // Clear input
        messageText = ""
        historyIndex = nil
    }

    private func clearTerminal() {
        for message in messages {
            modelContext.delete(message)
        }
    }

    private func setupBluetoothCallback() {
        bluetoothManager.onMessageReceived = { receivedMessage in
            let message = TerminalMessage(
                content: receivedMessage,
                direction: .received,
                deviceName: bluetoothManager.connectedDevice?.name
            )
            modelContext.insert(message)
        }
    }

    private func attemptAutoConnect() {
        // Check if remember last device is enabled
        guard settings.rememberLastDevice else { return }
        guard !settings.lastDeviceUUID.isEmpty else { return }
        guard bluetoothManager.bluetoothState == .poweredOn else { return }

        // Start scanning to find the remembered device
        bluetoothManager.startScanning()

        // Wait a bit for scan results, then check for the remembered device
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Look for the remembered device in discovered devices
            if let rememberedDevice = self.bluetoothManager.discoveredDevices.first(where: {
                $0.identifier.uuidString == self.settings.lastDeviceUUID
            }) {
                // Found it! Connect automatically
                self.bluetoothManager.connect(to: rememberedDevice)
            }
        }
    }

    // MARK: - Command History
    private func loadCommandHistory() {
        if let data = UserDefaults.standard.data(forKey: "commandHistory"),
           let history = try? JSONDecoder().decode([String].self, from: data) {
            commandHistory = history
        }
    }

    private func saveCommandHistory() {
        if let data = try? JSONEncoder().encode(commandHistory) {
            UserDefaults.standard.set(data, forKey: "commandHistory")
        }
    }

    private func addToCommandHistory(_ command: String) {
        // Remove if already exists
        commandHistory.removeAll { $0 == command }

        // Add to end
        commandHistory.append(command)

        // Keep only last N commands (from settings)
        if commandHistory.count > settings.commandHistorySize {
            commandHistory.removeFirst()
        }

        saveCommandHistory()
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }

        if historyIndex == nil {
            historyIndex = commandHistory.count - 1
        } else if let index = historyIndex, index > 0 {
            historyIndex = index - 1
        }

        if let index = historyIndex {
            messageText = commandHistory[index]
        }
    }

    private func navigateHistoryDown() {
        guard let index = historyIndex else { return }

        if index < commandHistory.count - 1 {
            historyIndex = index + 1
            messageText = commandHistory[historyIndex!]
        } else {
            historyIndex = nil
            messageText = ""
        }
    }

    // MARK: - Search & Filter
    private var filteredMessages: [TerminalMessage] {
        var filtered = displayedMessages

        // Apply direction filter
        if let direction = filterDirection {
            filtered = filtered.filter { $0.direction == direction }
        }

        // Apply time filter
        filtered = filtered.filter { message in
            filterTimeRange.contains(message.timestamp)
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { message in
                message.matches(searchText: searchText, caseSensitive: caseSensitive, useRegex: useRegex)
            }
        }

        return filtered
    }

    private var searchResults: [TerminalMessage] {
        guard !searchText.isEmpty else { return [] }
        return filteredMessages
    }

    private func navigateToNextResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchResult = (currentSearchResult + 1) % searchResults.count
    }

    private func navigateToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchResult = (currentSearchResult - 1 + searchResults.count) % searchResults.count
    }

    // MARK: - RSSI Indicator
    private var rssiIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: rssiIconName)
            Text("\(bluetoothManager.rssiValue) dBm")
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundColor(bluetoothManager.connectionQuality.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bluetoothManager.connectionQuality.color.opacity(0.1))
        .cornerRadius(4)
    }

    private var rssiIconName: String {
        let rssi = bluetoothManager.rssiValue
        if rssi == 0 { return "wifi.exclamationmark" }
        if rssi > -60 { return "wifi" }
        if rssi > -70 { return "wifi" }
        if rssi > -80 { return "wifi" }
        return "wifi.exclamationmark"
    }

    // MARK: - Favorites Bar
    private var favoritesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(favoriteMacros) { macro in
                    Button(action: {
                        bluetoothManager.sendMessage(macro.command)
                    }) {
                        Text(macro.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .disabled(bluetoothManager.connectionState != .connected)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Export
    private func generateExportString() -> String {
        let messagesToExport = filteredMessages
        guard !messagesToExport.isEmpty else { return "No messages to export" }

        switch settings.exportFormat {
        case "csv":
            var csv = "Timestamp,Direction,Device,Content\n"
            for message in messagesToExport {
                let device = message.deviceName ?? "None"
                let content = message.content.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\(message.timestamp),\(message.direction.rawValue),\(device),\"\(content)\"\n"
            }
            return csv

        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601

            struct MessageDTO: Codable {
                let timestamp: Date
                let content: String
                let direction: String
                let deviceName: String?
            }

            let dtos = messagesToExport.map { MessageDTO(timestamp: $0.timestamp, content: $0.content, direction: $0.direction.rawValue, deviceName: $0.deviceName) }
            if let data = try? encoder.encode(dtos), let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "Error generating JSON"

        default: // "text"
            var text = "--- iESP32 Terminal Log ---\n"
            text += "Exported on: \(Date())\n\n"
            for message in messagesToExport {
                let timestamp = "[\(message.timestamp)] "
                let direction = message.direction == .sent ? ">> " : "<< "
                text += "\(timestamp)\(direction)\(message.content)\n"
            }
            return text
        }
    }
}

// MARK: - FilterChip View
struct FilterChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.2))
        .foregroundColor(.blue)
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TerminalMessage.self, inMemory: true)
}
