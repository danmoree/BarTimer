//
//  NotificationManager.swift
//  BarTimer
//

import AppKit
import UserNotifications

/// Posts the "timer finished" alert, with a graceful fallback for when the user
/// has denied notification permission.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private enum Identifier {
        static let category = "com.bartimer.timerFinished"
        static let restartAction = "com.bartimer.restart"
        static let slotKey = "slot"
    }

    /// Invoked when the user taps "Start Again" on a delivered notification.
    var onRestartRequest: ((Int) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self

        let restart = UNNotificationAction(
            identifier: Identifier.restartAction,
            title: "Start Again",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [restart],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// The completion chime, from /System/Library/Sounds. Bell-ish options, from
    /// roundest to driest: Glass, Ping, Bottle, Tink.
    private static let chime = NSSound(named: NSSound.Name("Ping"))

    /// Announces a completed countdown: one chime, plus a banner if notifications
    /// are permitted. A finished timer is therefore never both silent and invisible.
    func notifyFinished(preset: TimerPreset, slot: Int, playSound: Bool) {
        if playSound {
            ring()
        }

        Task {
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Timer Finished"
            content.body = "\(preset.displayName) — \(preset.durationDescription) is up."
            // Silent: the chime above is the sound, so the alert can't double it.
            content.sound = nil
            content.categoryIdentifier = Identifier.category
            content.userInfo = [Identifier.slotKey: slot]

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func ring() {
        guard let chime = Self.chime else { return }
        // Restart rather than no-op if two timers land together.
        if chime.isPlaying { chime.stop() }
        chime.play()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // BarTimer has no windows, so it's usually "in the background" anyway —
        // but be explicit so the banner shows even when it isn't. No `.sound`:
        // `notifyFinished` already played the chime.
        [.banner]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Identifier.restartAction,
              let slot = response.notification.request.content.userInfo[Identifier.slotKey] as? Int
        else { return }

        await MainActor.run {
            onRestartRequest?(slot)
        }
    }
}
