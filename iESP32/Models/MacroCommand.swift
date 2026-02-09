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
    var timestamp: Date

    init(name: String, command: String, category: String = "Default") {
        self.name = name
        self.command = command
        self.category = category
        self.timestamp = Date()
    }
}
