//
//  Diagnostics.swift
//  iESP32
//

import Foundation

struct BLEEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: String
    let message: String

    init(level: String, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
}

struct RawPacket: Identifiable, Codable {
    enum Direction: String, Codable {
        case tx
        case rx
    }

    let id: UUID
    let timestamp: Date
    let direction: Direction
    let byteCount: Int
    let payloadHex: String

    init(direction: Direction, payload: Data) {
        self.id = UUID()
        self.timestamp = Date()
        self.direction = direction
        self.byteCount = payload.count
        self.payloadHex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
