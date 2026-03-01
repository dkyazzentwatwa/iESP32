//
//  ExportService.swift
//  iESP32
//

import Foundation

enum ExportServiceError: Error {
    case noDocumentsDirectory
    case unsupportedFormat
}

enum ExportFormat: String {
    case text
    case json
    case csv
}

private struct TerminalMessageExportRecord: Codable {
    let id: UUID
    let timestamp: Date
    let direction: String
    let content: String
    let deviceName: String?
    let sessionID: UUID?
    let deliveryStatus: String?
}

private struct DiagnosticsExportRecord: Codable {
    let exportedAt: Date
    let events: [BLEEvent]
    let rawPackets: [RawPacket]
}

enum ExportService {
    static let userVisibleExportsPathHint = "Files > On My iPhone > iESP32 > Exports"

    static func exportMessages(
        messages: [TerminalMessage],
        formatRawValue: String,
        reason: String = "manual"
    ) throws -> URL {
        guard let format = ExportFormat(rawValue: formatRawValue) else {
            throw ExportServiceError.unsupportedFormat
        }

        let exportsDirectory = try exportsDirectoryURL()
        let fileDate = fileTimestampString(from: Date())
        let fileURL = exportsDirectory.appendingPathComponent("terminal-\(reason)-\(fileDate).\(fileExtension(for: format))")

        let data: Data
        switch format {
        case .text:
            data = textExportData(from: messages)
        case .json:
            data = try jsonExportData(from: messages)
        case .csv:
            data = csvExportData(from: messages)
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func exportDiagnostics(events: [BLEEvent], rawPackets: [RawPacket]) throws -> URL {
        let exportsDirectory = try exportsDirectoryURL()
        let fileDate = fileTimestampString(from: Date())
        let fileURL = exportsDirectory.appendingPathComponent("diagnostics-\(fileDate).json")

        let payload = DiagnosticsExportRecord(
            exportedAt: Date(),
            events: events,
            rawPackets: rawPackets
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: .atomic)

        return fileURL
    }

    private static func exportsDirectoryURL() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportServiceError.noDocumentsDirectory
        }

        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: exportsDirectory.path) {
            try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        }
        return exportsDirectory
    }

    private static func fileTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func displayTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private static func fileExtension(for format: ExportFormat) -> String {
        switch format {
        case .text:
            return "txt"
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }

    private static func textExportData(from messages: [TerminalMessage]) -> Data {
        let lines = messages.map { message in
            let timestamp = displayTimestampString(from: message.timestamp)
            let direction = message.direction.rawValue.uppercased()
            return "[\(timestamp)] \(direction): \(message.content)"
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func jsonExportData(from messages: [TerminalMessage]) throws -> Data {
        let records = messages.map {
            TerminalMessageExportRecord(
                id: $0.messageID,
                timestamp: $0.timestamp,
                direction: $0.direction.rawValue,
                content: $0.content,
                deviceName: $0.deviceName,
                sessionID: $0.sessionID,
                deliveryStatus: $0.deliveryStatus?.rawValue
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    private static func csvExportData(from messages: [TerminalMessage]) -> Data {
        func escape(_ field: String) -> String {
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }

        var rows = ["id,timestamp,direction,deviceName,sessionID,deliveryStatus,content"]
        rows.append(contentsOf: messages.map { message in
            let fields = [
                message.messageID.uuidString,
                displayTimestampString(from: message.timestamp),
                message.direction.rawValue,
                message.deviceName ?? "",
                message.sessionID?.uuidString ?? "",
                message.deliveryStatus?.rawValue ?? "",
                message.content
            ]
            return fields.map(escape).joined(separator: ",")
        })
        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }
}
