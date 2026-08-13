//
//  SettingsWindowController.swift
//  BarTimer
//

import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain `NSWindow`.
///
/// BarTimer runs as an accessory app with no `WindowGroup`, so it manages this
/// one window itself instead of relying on SwiftUI's `Settings` scene.
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "BarTimer Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("BarTimer.settings")
            // Reopen where the user last left it; centre only on first run.
            if !window.setFrameUsingName("BarTimer.settings") {
                window.center()
            }
            self.window = window
        }

        // An accessory app isn't frontmost by default, so ask for activation
        // or the window opens behind whatever the user was using.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
