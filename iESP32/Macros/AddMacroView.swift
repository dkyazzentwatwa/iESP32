//
//  AddMacroView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI
import SwiftData

struct AddMacroView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    var macro: MacroCommand?

    @State private var name = ""
    @State private var command = ""
    @State private var category = "Default"
    @State private var isFavorite = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Command Details")) {
                    TextField("Name (e.g., Get Version)", text: $name)
                    TextField("Command (e.g., version)", text: $command)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }

                Section(header: Text("Options")) {
                    TextField("Category", text: $category)
                    Toggle("Add to Favorites", isOn: $isFavorite)
                }
            }
            .navigationTitle(macro == nil ? "Add Command" : "Edit Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty || command.isEmpty)
                }
            }
            .onAppear {
                if let macro = macro {
                    name = macro.name
                    command = macro.command
                    category = macro.category
                    isFavorite = macro.isFavorite
                }
            }
        }
    }

    private func save() {
        if let macro = macro {
            macro.name = name
            macro.command = command
            macro.category = category
            macro.isFavorite = isFavorite
        } else {
            let newMacro = MacroCommand(name: name, command: command, category: category, isFavorite: isFavorite)
            modelContext.insert(newMacro)
        }
        dismiss()
    }
}
