//
//  BarTimerApp.swift
//  BarTimer
//
//  BarTimer uses the AppKit lifecycle rather than SwiftUI's `App`: it owns no
//  scenes, only menu bar items, and it manages its settings window directly.
//

import AppKit

@main
enum BarTimerApp {
    // Explicitly main-actor isolated so the delegate's isolation matches;
    // plain top-level code would be nonisolated.
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // `NSApplication.delegate` is a weak reference, so hold this one alive
        // for the lifetime of the run loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
