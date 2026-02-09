//
//  FilterOptionsView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct FilterOptionsView: View {
    @Binding var filterDirection: MessageDirection?
    @Binding var filterTimeRange: TimeRange
    @Environment(\.dismiss) var dismiss

    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date().addingTimeInterval(-86400)
    @State private var customEndDate = Date()

    var body: some View {
        NavigationView {
            Form {
                // Direction Filter
                Section {
                    Picker("Message Direction", selection: $filterDirection) {
                        Text("All Messages").tag(nil as MessageDirection?)
                        Text("Sent Only").tag(MessageDirection.sent as MessageDirection?)
                        Text("Received Only").tag(MessageDirection.received as MessageDirection?)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Direction")
                } footer: {
                    Text("Filter messages by send/receive direction")
                }

                // Time Range Filter
                Section {
                    Button(action: { filterTimeRange = .allTime }) {
                        HStack {
                            Text("All Time")
                            Spacer()
                            if filterTimeRange == .allTime {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: { filterTimeRange = .lastHour }) {
                        HStack {
                            Text("Last Hour")
                            Spacer()
                            if filterTimeRange == .lastHour {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: { filterTimeRange = .last24Hours }) {
                        HStack {
                            Text("Last 24 Hours")
                            Spacer()
                            if filterTimeRange == .last24Hours {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: { filterTimeRange = .last7Days }) {
                        HStack {
                            Text("Last 7 Days")
                            Spacer()
                            if filterTimeRange == .last7Days {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: { showCustomDatePicker = true }) {
                        HStack {
                            Text("Custom Range")
                            Spacer()
                            if case .custom = filterTimeRange {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Time Range")
                } footer: {
                    Text("Filter messages by timestamp")
                }

                // Clear Filters
                Section {
                    Button("Clear All Filters") {
                        filterDirection = nil
                        filterTimeRange = .allTime
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDateRangePicker
            }
        }
    }

    private var customDateRangePicker: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Custom Date Range")
                }
            }
            .navigationTitle("Select Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showCustomDatePicker = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        filterTimeRange = .custom(start: customStartDate, end: customEndDate)
                        showCustomDatePicker = false
                    }
                }
            }
        }
    }
}
