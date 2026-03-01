//
//  TerminalMessage.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation
import SwiftData

enum MessageDeliveryStatus: String, Codable {
    case pending
    case delivered
    case failed
}

@Model
final class TerminalMessage {
    var messageID: UUID
    var timestamp: Date
    var content: String
    var direction: MessageDirection
    var deviceName: String?
    var deliveryStatusRaw: String?
    var sessionID: UUID?
    var isFavorite: Bool

    var deliveryStatus: MessageDeliveryStatus? {
        get {
            guard let deliveryStatusRaw else { return nil }
            return MessageDeliveryStatus(rawValue: deliveryStatusRaw)
        }
        set {
            deliveryStatusRaw = newValue?.rawValue
        }
    }

    init(
        content: String,
        direction: MessageDirection,
        deviceName: String? = nil,
        sessionID: UUID? = nil,
        deliveryStatus: MessageDeliveryStatus? = nil,
        isFavorite: Bool = false
    ) {
        self.messageID = UUID()
        self.timestamp = Date()
        self.content = content
        self.direction = direction
        self.deviceName = deviceName
        self.deliveryStatusRaw = deliveryStatus?.rawValue
        self.sessionID = sessionID
        self.isFavorite = isFavorite
    }
}

enum MessageDirection: String, Codable {
    case sent
    case received
}
