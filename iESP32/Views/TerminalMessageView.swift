//
//  TerminalMessageView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct TerminalMessageView: View {
    let message: TerminalMessage
    @ObservedObject var settings: SettingsManager
    let lineNumber: Int?
    let isHighlighted: Bool

    // MARK: - Static Formatters (performance optimization)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let timeWithMsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private var timeString: String {
        switch settings.timestampFormat {
        case "HH:mm:ss.SSS":
            return Self.timeWithMsFormatter.string(from: message.timestamp)
        default:
            return Self.timeFormatter.string(from: message.timestamp)
        }
    }

    private var relativeTimeString: String {
        let interval = Date().timeIntervalSince(message.timestamp)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }

    private var displayTimeString: String {
        settings.timestampFormat == "relative" ? relativeTimeString : timeString
    }

    private var directionSymbol: String {
        message.direction == .sent ? ">>" : "<<"
    }

    private var messageColor: Color {
        message.direction == .sent ? settings.sentMessageColor : settings.receivedMessageColor
    }

    private var statusText: String? {
        guard message.direction == .sent, let status = message.deliveryStatus else { return nil }
        switch status {
        case .pending:
            return "sending"
        case .delivered:
            return "sent"
        case .failed:
            return "failed"
        }
    }

    private var statusColor: Color {
        guard let status = message.deliveryStatus else { return .secondary }
        switch status {
        case .pending:
            return .orange
        case .delivered:
            return .green
        case .failed:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Show line number if enabled
            if settings.showLineNumbers, let lineNum = lineNumber {
                Text("\(lineNum)")
                    .font(.system(size: settings.fontSize * 0.8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            if settings.showTimestamps {
                Text("[\(displayTimeString)]")
                    .font(.system(size: settings.fontSize * 0.8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(directionSymbol)
                .font(.system(size: settings.fontSize, design: .monospaced))
                .foregroundColor(messageColor)

            Text(message.content)
                .font(.system(size: settings.fontSize, design: .monospaced))
                .foregroundColor(messageColor)
                .textSelection(.enabled)
                .lineLimit(settings.textWrapping ? nil : 1)

            if settings.showMessageByteCount {
                Text("(\(message.content.utf8.count) bytes)")
                    .font(.system(size: settings.fontSize * 0.7, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let statusText {
                Text("[\(statusText)]")
                    .font(.system(size: settings.fontSize * 0.65, design: .monospaced))
                    .foregroundColor(statusColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.yellow.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}
