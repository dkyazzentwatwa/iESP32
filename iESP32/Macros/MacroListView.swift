//
//  MacroListView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI
import SwiftData

struct MacroListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MacroCommand.name) private var macros: [MacroCommand]

    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss

    @State private var showAddMacro = false
    @State private var macroToEdit: MacroCommand?

    var body: some View {
        NavigationView {
            List {
                if macros.isEmpty {
                    Section {
                        Text("No quick commands saved yet. Add one to quickly send frequent commands to your ESP32.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(macros) { macro in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(macro.name)
                                    .font(.headline)
                                if macro.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                }
                            }
                            Text(macro.command)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: {
                            bluetoothManager.sendMessage(macro.command)
                            dismiss()
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.bordered)
                        .disabled(bluetoothManager.connectionState != .connected)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(macro)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            macroToEdit = macro
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)

                        Button {
                            macro.isFavorite.toggle()
                        } label: {
                            Label(macro.isFavorite ? "Unfavorite" : "Favorite", systemImage: macro.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
            }
            .navigationTitle("Quick Commands")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddMacro = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddMacro) {
                AddMacroView()
            }
            .sheet(item: $macroToEdit) { macro in
                AddMacroView(macro: macro)
            }
        }
    }
}
