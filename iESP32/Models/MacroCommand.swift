//
//  MacroCommand.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation
import SwiftData

@Model
final class MacroCommand {
    var name: String
    var command: String
    var category: String
    var isFavorite: Bool
    var timestamp: Date

    init(name: String, command: String, category: String = "Default", isFavorite: Bool = false) {
        self.name = name
        self.command = command
        self.category = category
        self.isFavorite = isFavorite
        self.timestamp = Date()
    }
}
