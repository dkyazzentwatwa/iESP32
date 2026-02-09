//
//  SearchBarView.swift
//  iESP32
//
//  Created by Claude on 2026-01-27.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var caseSensitive: Bool
    @Binding var useRegex: Bool
    @Binding var showFilters: Bool

    var resultCount: Int
    var currentResult: Int
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search messages...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(8)

                // Filter button
                Button(action: { showFilters = true }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }

            // Search options and results
            if !searchText.isEmpty {
                HStack {
                    // Options
                    Toggle("Aa", isOn: $caseSensitive)
                        .toggleStyle(.button)
                        .font(.caption)

                    Toggle(".*", isOn: $useRegex)
                        .toggleStyle(.button)
                        .font(.caption)

                    Spacer()

                    // Results counter
                    if resultCount > 0 {
                        Text("\(currentResult + 1) of \(resultCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Navigation buttons
                        Button(action: onPrevious) {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(resultCount == 0)

                        Button(action: onNext) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(resultCount == 0)
                    } else {
                        Text("No results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }
}
