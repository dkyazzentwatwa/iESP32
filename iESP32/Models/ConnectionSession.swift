//
//  ConnectionSession.swift
//  iESP32
//

import Foundation
import SwiftData

@Model
final class ConnectionSession {
    var sessionID: UUID
    var startedAt: Date
    var endedAt: Date?
    var deviceName: String
    var deviceUUID: String
    var bytesSent: Int
    var bytesReceived: Int
    var messagesSent: Int
    var messagesReceived: Int

    init(deviceName: String, deviceUUID: String) {
        self.sessionID = UUID()
        self.startedAt = Date()
        self.endedAt = nil
        self.deviceName = deviceName
        self.deviceUUID = deviceUUID
        self.bytesSent = 0
        self.bytesReceived = 0
        self.messagesSent = 0
        self.messagesReceived = 0
    }

    func close(bytesSent: Int, bytesReceived: Int, messagesSent: Int, messagesReceived: Int) {
        self.endedAt = Date()
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
    }
}
