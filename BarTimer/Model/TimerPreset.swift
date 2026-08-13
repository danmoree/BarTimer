//
//  TimerPreset.swift
//  BarTimer
//

import Foundation

/// A single configurable countdown preset. BarTimer always keeps exactly
/// `AppSettings.slotCount` presets around; `AppSettings.visibleCount` decides
/// how many of them get a menu bar item.
struct TimerPreset: Codable, Equatable {
    /// Custom name shown in the menu bar. Empty means "use `autoLabel`".
    var title: String
    /// Length of the countdown, in seconds.
    var duration: TimeInterval

    init(title: String = "", minutes: Int, seconds: Int = 0) {
        self.title = title
        self.duration = TimeInterval(minutes * 60 + seconds)
    }

    /// Compact label derived from the duration, e.g. `5m`, `1h30m`, `90s`.
    var autoLabel: String {
        let total = Int(duration.rounded())
        guard total > 0 else { return "--" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 { parts.append("\(seconds)s") }
        return parts.joined()
    }

    /// What actually gets drawn in the menu bar.
    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? autoLabel : trimmed
    }

    /// Spelled-out duration for menus and notifications, e.g. "1 minute 30 seconds".
    var durationDescription: String {
        let total = Int(duration.rounded())
        guard total > 0 else { return "no duration set" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// A preset with no duration can't be started; the UI nudges the user to fix it.
    var isRunnable: Bool { duration >= 1 }
}

/// Formats a remaining-seconds count for the menu bar: `4:59`, `1:05:30`.
func formatCountdown(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
