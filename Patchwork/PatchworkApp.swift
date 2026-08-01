//
//  PatchworkApp.swift
//  Patchwork
//
//  Created by chee on 2026-07-31.
//

import SwiftUI
import WebKit

@main
struct PatchworkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Show Web Inspector") {
                    let webView = AppModel.shared.webView
                    guard webView.responds(to: Selector(("_inspector"))),
                          let inspector = webView.perform(Selector(("_inspector")))?
                            .takeUnretainedValue() as? NSObject,
                          inspector.responds(to: Selector(("show")))
                    else { return }
                    inspector.perform(Selector(("show")))
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        #if os(macOS)
        MenuBarExtra("Patchwork", systemImage: "square.grid.2x2") {
            MenuBarView()
        }
        #endif
    }
}
