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

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = settings.timestampFormat == "relative" ? "HH:mm:ss" : settings.timestampFormat
        return formatter.string(from: message.timestamp)
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

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
