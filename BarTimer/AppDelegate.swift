//
//  AppDelegate.swift
//  BarTimer
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = MenuBarCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no windows at launch.
        NSApp.setActivationPolicy(.accessory)

        MainMenu.install(target: self, settingsAction: #selector(openSettings))
        NotificationManager.shared.configure()
        coordinator.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc private func openSettings() {
        coordinator.openSettings()
    }
}
