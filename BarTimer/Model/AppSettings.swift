//
//  AppSettings.swift
//  BarTimer
//

import Combine
import Foundation

/// User configuration, persisted to `UserDefaults` on every change.
final class AppSettings: ObservableObject {
    /// How many presets the app keeps configured. The user chooses how many of
    /// these are actually shown via `visibleCount`.
    static let slotCount = 3
    static let shared = AppSettings()

    @Published var presets: [TimerPreset] { didSet { persist() } }

    /// Number of menu bar items to show, 1...3.
    @Published var visibleCount: Int {
        didSet {
            let clamped = min(Self.slotCount, max(1, visibleCount))
            // Assigning inside didSet does not re-trigger the observer.
            if clamped != visibleCount { visibleCount = clamped }
            persist()
        }
    }

    @Published var playSound: Bool { didSet { persist() } }

    private enum Key {
        static let presets = "presets"
        static let visibleCount = "visibleCount"
        static let playSound = "playSound"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = (defaults.data(forKey: Key.presets))
            .flatMap { try? JSONDecoder().decode([TimerPreset].self, from: $0) }
        self.presets = Self.normalize(stored ?? Self.defaultPresets)

        let storedCount = defaults.object(forKey: Key.visibleCount) as? Int
        self.visibleCount = min(Self.slotCount, max(1, storedCount ?? Self.slotCount))

        self.playSound = (defaults.object(forKey: Key.playSound) as? Bool) ?? true
    }

    static var defaultPresets: [TimerPreset] {
        [
            TimerPreset(minutes: 5),
            TimerPreset(minutes: 15),
            TimerPreset(minutes: 30),
        ]
    }

    /// Guarantees the array is always exactly `slotCount` long, so slot indices
    /// are always safe to subscript.
    private static func normalize(_ presets: [TimerPreset]) -> [TimerPreset] {
        var result = Array(presets.prefix(slotCount))
        let fallback = defaultPresets
        while result.count < slotCount {
            result.append(fallback[result.count])
        }
        return result
    }

    func preset(at slot: Int) -> TimerPreset? {
        presets.indices.contains(slot) ? presets[slot] : nil
    }

    func isVisible(slot: Int) -> Bool { slot < visibleCount }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Key.presets)
        }
        defaults.set(visibleCount, forKey: Key.visibleCount)
        defaults.set(playSound, forKey: Key.playSound)
    }
}
