//
//  iESP32App.swift
//  iESP32
//
//  Created by David KyazzeNtwatwa  on 1/27/26.
//

import SwiftUI
import SwiftData

@main
struct iESP32App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TerminalMessage.self,
            MacroCommand.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
