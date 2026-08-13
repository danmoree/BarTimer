//
//  LaunchAtLogin.swift
//  BarTimer
//

import ServiceManagement

/// Thin wrapper over `SMAppService` so the settings UI doesn't have to care
/// about the registration details.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            // `unregister()` throws if the app was never registered.
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
