//
//  TerminalMessage+Filtering.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import Foundation

enum TimeRange: Equatable {
    case allTime
    case lastHour
    case last24Hours
    case last7Days
    case custom(start: Date, end: Date)

    func contains(_ date: Date) -> Bool {
        switch self {
        case .allTime:
            return true
        case .lastHour:
            return date > Date().addingTimeInterval(-3600)
        case .last24Hours:
            return date > Date().addingTimeInterval(-86400)
        case .last7Days:
            return date > Date().addingTimeInterval(-604800)
        case .custom(let start, let end):
            return date >= start && date <= end
        }
    }

    var displayText: String {
        switch self {
        case .allTime:
            return "All Time"
        case .lastHour:
            return "Last Hour"
        case .last24Hours:
            return "Last 24 Hours"
        case .last7Days:
            return "Last 7 Days"
        case .custom:
            return "Custom Range"
        }
    }
}

extension TerminalMessage {
    func matches(searchText: String, caseSensitive: Bool, useRegex: Bool) -> Bool {
        guard !searchText.isEmpty else { return true }

        if useRegex {
            return content.range(of: searchText, options: .regularExpression) != nil
        } else {
            let options: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
            return content.range(of: searchText, options: options) != nil
        }
    }
}
