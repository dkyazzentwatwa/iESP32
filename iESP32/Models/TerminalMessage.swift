//
//  TerminalMessage.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation
import SwiftData

@Model
final class TerminalMessage {
    var timestamp: Date
    var content: String
    var direction: MessageDirection
    var deviceName: String?

    init(content: String, direction: MessageDirection, deviceName: String? = nil) {
        self.timestamp = Date()
        self.content = content
        self.direction = direction
        self.deviceName = deviceName
    }
}

enum MessageDirection: String, Codable {
    case sent
    case received
}
