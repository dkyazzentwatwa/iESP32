//
//  ContentView.swift
//  iESP32
//
//  Created by David KyazzeNtwatwa  on 1/27/26.
//

import SwiftUI
import SwiftData
import CoreBluetooth

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalMessage.timestamp, order: .forward) private var messages: [TerminalMessage]

    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var settings = SettingsManager()
    @State private var messageText = ""
    @State private var showDevicePicker = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @State private var currentSession: ConnectionSession?
    @State private var pendingAutoConnect = false
    @State private var autoConnectTask: Task<Void, Never>?
    @State private var showAppAlert = false
    @State private var appAlertMessage = ""
    @State private var shareItem: ExportShareItem?
    @FocusState private var isTextFieldFocused: Bool

    // Search & Filter State
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var filterDirection: MessageDirection? = nil
    @State private var filterTimeRange: TimeRange = .allTime
    @State private var showFilters = false
    @State private var currentSearchResult = 0
    @State private var selectedSearchMessageID: PersistentIdentifier?

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
                }

                if filterDirection != nil || filterTimeRange != .allTime {
                    activeFiltersView
                }

                connectionBar
                    .padding()
                    .background(Color(uiColor: .systemBackground))

                Divider()

                terminalView

                Divider()

                inputArea
                    .padding()
                    .background(Color(uiColor: .systemBackground))
            }
            .background(settings.backgroundColor.opacity(0.95))
            .navigationTitle("iESP32 Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: toggleSearch) {
                        Image(systemName: showSearch ? "xmark" : "magnifyingglass")
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
                configureCallbacks()
                loadCommandHistory()
                attemptAutoConnect()
            }
            .onDisappear {
                autoConnectTask?.cancel()
            }
            .onChange(of: bluetoothManager.bluetoothState) { _, newState in
                if newState == .poweredOn {
                    attemptAutoConnectIfReady()
                }
            }
            .onChange(of: searchText) { _, _ in
                refreshSearchSelection()
            }
            .onChange(of: caseSensitive) { _, _ in
                refreshSearchSelection()
            }
            .onChange(of: useRegex) { _, _ in
                refreshSearchSelection()
            }
            .onChange(of: filterDirection) { _, _ in
                refreshSearchSelection()
            }
            .onChange(of: filterTimeRange) { _, _ in
                refreshSearchSelection()
            }
            .sheet(isPresented: $showDevicePicker) {
                DevicePickerView(bluetoothManager: bluetoothManager, settings: settings)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    settings: settings,
                    bluetoothManager: bluetoothManager,
                    onExportRequested: { exportMessages(reason: "manual", presentShareSheet: true) },
                    onDiagnosticsExportRequested: { exportDiagnostics(presentShareSheet: true) },
                    onClearDiagnosticsRequested: {
                        bluetoothManager.clearDiagnostics()
                        showAppMessage("Cleared in-memory diagnostics logs.")
                    }
                )
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(activityItems: [item.url])
            }
            .sheet(isPresented: $showStats) {
                ConnectionStatsView(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: $showFilters) {
                FilterOptionsView(filterDirection: $filterDirection, filterTimeRange: $filterTimeRange)
            }
            .alert(isPresented: $bluetoothManager.showAlert) {
                Alert(
                    title: Text("Bluetooth"),
                    message: Text(bluetoothManager.alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("iESP32", isPresented: $showAppAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appAlertMessage)
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
            return nil
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
            if !bluetoothManager.isTransportReady {
                return "Initializing..."
            }
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
                    ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                        TerminalMessageView(
                            message: message,
                            settings: settings,
                            lineNumber: index + 1,
                            isHighlighted: message.id == selectedSearchMessageID
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if settings.autoScroll, let lastMessage = visibleMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: selectedSearchMessageID) { _, newID in
                guard let newID else { return }
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private var displayedMessages: [TerminalMessage] {
        guard settings.messageBufferSize > 0 else { return messages }
        let count = messages.count
        let bufferSize = settings.messageBufferSize
        return count > bufferSize ? Array(messages.suffix(bufferSize)) : messages
    }

    private var baseFilteredMessages: [TerminalMessage] {
        var filtered = displayedMessages

        if let direction = filterDirection {
            filtered = filtered.filter { $0.direction == direction }
        }

        filtered = filtered.filter { message in
            filterTimeRange.contains(message.timestamp)
        }

        return filtered
    }

    private var visibleMessages: [TerminalMessage] {
        if !searchText.isEmpty {
            return searchResults
        }

        if showSearch || filterDirection != nil || filterTimeRange != .allTime {
            return baseFilteredMessages
        }

        return displayedMessages
    }

    // MARK: - Input Area
    private var inputArea: some View {
        HStack(spacing: 12) {
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

            TextField("Enter command...", text: $messageText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(messageText.isEmpty || bluetoothManager.connectionState != .connected || !bluetoothManager.isTransportReady)

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

        let message = TerminalMessage(
            content: messageText,
            direction: .sent,
            deviceName: bluetoothManager.connectedDevice?.name,
            sessionID: currentSession?.sessionID,
            deliveryStatus: .pending
        )
        modelContext.insert(message)

        let sent = bluetoothManager.sendMessage(messageText, messageID: message.messageID)
        if !sent {
            message.deliveryStatus = .failed
        }

        addToCommandHistory(messageText)
        enforceMessageRetentionLimit()

        messageText = ""
        historyIndex = nil
    }

    private func clearTerminal() {
        // Perform deletions in batches to avoid blocking UI
        let messagesToDelete = Array(messages)
        selectedSearchMessageID = nil

        // Delete in batches of 100 with yields between batches
        Task {
            let batchSize = 100
            for i in stride(from: 0, to: messagesToDelete.count, by: batchSize) {
                let end = min(i + batchSize, messagesToDelete.count)
                let batch = messagesToDelete[i..<end]

                await MainActor.run {
                    for message in batch {
                        modelContext.delete(message)
                    }
                }

                // Yield to allow UI updates between batches
                if end < messagesToDelete.count {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
    }

    private func configureCallbacks() {
        bluetoothManager.onMessageReceived = { receivedMessage in
            let message = TerminalMessage(
                content: receivedMessage,
                direction: .received,
                deviceName: bluetoothManager.connectedDevice?.name,
                sessionID: currentSession?.sessionID
            )
            modelContext.insert(message)
            enforceMessageRetentionLimit()
        }

        bluetoothManager.onMessageDeliveryStatusChanged = { messageID, status in
            updateDeliveryStatus(messageID: messageID, status: status)
        }

        bluetoothManager.onConnectionStateChanged = { newState in
            handleConnectionStateChange(newState)
        }
    }

    private func message(with messageID: UUID) -> TerminalMessage? {
        var descriptor = FetchDescriptor<TerminalMessage>(
            predicate: #Predicate<TerminalMessage> { message in
                message.messageID == messageID
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func updateDeliveryStatus(
        messageID: UUID,
        status: MessageDeliveryStatus,
        retriesRemaining: Int = 1
    ) {
        if let matchingMessage = message(with: messageID) {
            matchingMessage.deliveryStatus = status
            return
        }

        guard retriesRemaining > 0 else { return }

        DispatchQueue.main.async {
            updateDeliveryStatus(
                messageID: messageID,
                status: status,
                retriesRemaining: retriesRemaining - 1
            )
        }
    }

    private func attemptAutoConnect() {
        guard settings.rememberLastDevice else {
            pendingAutoConnect = false
            return
        }
        guard !settings.lastDeviceUUID.isEmpty else {
            pendingAutoConnect = false
            return
        }

        pendingAutoConnect = true
        attemptAutoConnectIfReady()
    }

    private func attemptAutoConnectIfReady() {
        guard pendingAutoConnect else { return }
        guard bluetoothManager.bluetoothState == .poweredOn else { return }
        guard bluetoothManager.connectionState == .disconnected else {
            pendingAutoConnect = false
            return
        }

        autoConnectTask?.cancel()
        bluetoothManager.startScanning()

        autoConnectTask = Task { @MainActor in
            let timeout = Date().addingTimeInterval(Double(max(settings.scanDuration, 5)))

            while Date() < timeout, !Task.isCancelled, pendingAutoConnect {
                if let rememberedDevice = bluetoothManager.discoveredDevices.first(where: {
                    $0.identifier.uuidString == settings.lastDeviceUUID
                }) {
                    pendingAutoConnect = false
                    bluetoothManager.connect(to: rememberedDevice)
                    return
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            pendingAutoConnect = false
        }
    }

    private func handleConnectionStateChange(_ newState: ConnectionState) {
        switch newState {
        case .connected:
            guard currentSession == nil else { return }
            guard let connectedDevice = bluetoothManager.connectedDevice else { return }

            let session = ConnectionSession(
                deviceName: connectedDevice.name ?? "Unknown",
                deviceUUID: connectedDevice.identifier.uuidString
            )
            modelContext.insert(session)
            currentSession = session

        case .disconnected:
            closeCurrentSessionAndExportIfNeeded()

        case .connecting, .scanning:
            break
        }
    }

    private func closeCurrentSessionAndExportIfNeeded() {
        guard let currentSession else { return }

        currentSession.close(
            bytesSent: bluetoothManager.bytesSent,
            bytesReceived: bluetoothManager.bytesReceived,
            messagesSent: bluetoothManager.messagesSent,
            messagesReceived: bluetoothManager.messagesReceived
        )

        let sessionID = currentSession.sessionID
        self.currentSession = nil

        if settings.autoExportOnDisconnect {
            let sessionMessages = messages(for: sessionID)
            exportMessages(reason: "disconnect", customMessages: sessionMessages, presentShareSheet: false)
        }
    }

    private func messages(for sessionID: UUID) -> [TerminalMessage] {
        let descriptor = FetchDescriptor<TerminalMessage>(
            predicate: #Predicate<TerminalMessage> { message in
                message.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func enforceMessageRetentionLimit() {
        guard settings.messageBufferSize > 0 else { return }
        let overflow = messages.count - settings.messageBufferSize
        guard overflow > 0 else { return }

        // Delete in smaller batches to avoid blocking UI
        let messagesToDelete = Array(messages.prefix(overflow))
        let batchSize = min(overflow, 50) // Delete at most 50 at a time

        Task {
            for i in 0..<batchSize {
                await MainActor.run {
                    modelContext.delete(messagesToDelete[i])
                }
            }
        }
    }

    private func showAppMessage(_ message: String) {
        appAlertMessage = message
        showAppAlert = true
    }

    private func exportMessages(
        reason: String,
        customMessages: [TerminalMessage]? = nil,
        presentShareSheet: Bool
    ) {
        let data = customMessages ?? messages
        guard !data.isEmpty else {
            showAppMessage("No terminal messages to export.")
            return
        }

        do {
            let fileURL = try ExportService.exportMessages(
                messages: data,
                formatRawValue: settings.exportFormat,
                reason: reason
            )
            if presentShareSheet {
                shareItem = ExportShareItem(url: fileURL)
                showAppMessage("Exported \(data.count) messages. Share or Save to Files from the sheet.")
            } else {
                showAppMessage(
                    "Exported \(data.count) messages to \(fileURL.lastPathComponent).\nFind it in \(ExportService.userVisibleExportsPathHint)."
                )
            }
        } catch {
            showAppMessage("Export failed: \(error.localizedDescription)")
        }
    }

    private func exportDiagnostics(presentShareSheet: Bool) {
        do {
            let fileURL = try ExportService.exportDiagnostics(
                events: bluetoothManager.bleEventLog,
                rawPackets: bluetoothManager.rawPackets
            )
            if presentShareSheet {
                shareItem = ExportShareItem(url: fileURL)
                showAppMessage("Diagnostics exported. Share or Save to Files from the sheet.")
            } else {
                showAppMessage(
                    "Diagnostics exported to \(fileURL.lastPathComponent).\nFind it in \(ExportService.userVisibleExportsPathHint)."
                )
            }
        } catch {
            showAppMessage("Diagnostics export failed: \(error.localizedDescription)")
        }
    }

    private func toggleSearch() {
        withAnimation {
            showSearch.toggle()
        }

        if !showSearch {
            searchText = ""
            selectedSearchMessageID = nil
            currentSearchResult = 0
        } else {
            refreshSearchSelection()
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
        commandHistory.removeAll { $0 == command }
        commandHistory.append(command)

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
            if let historyIndex {
                messageText = commandHistory[historyIndex]
            }
        } else {
            historyIndex = nil
            messageText = ""
        }
    }

    // MARK: - Search & Filter
    private var searchResults: [TerminalMessage] {
        guard !searchText.isEmpty else { return [] }
        return baseFilteredMessages.filter { message in
            message.matches(searchText: searchText, caseSensitive: caseSensitive, useRegex: useRegex)
        }
    }

    private func refreshSearchSelection() {
        guard !searchResults.isEmpty else {
            currentSearchResult = 0
            selectedSearchMessageID = nil
            return
        }

        if currentSearchResult >= searchResults.count {
            currentSearchResult = 0
        }

        selectedSearchMessageID = searchResults[currentSearchResult].id
    }

    private func navigateToNextResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchResult = (currentSearchResult + 1) % searchResults.count
        selectedSearchMessageID = searchResults[currentSearchResult].id
    }

    private func navigateToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchResult = (currentSearchResult - 1 + searchResults.count) % searchResults.count
        selectedSearchMessageID = searchResults[currentSearchResult].id
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
