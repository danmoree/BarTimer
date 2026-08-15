//
//  MenuBarCoordinator.swift
//  BarTimer
//

import AppKit
import Combine

/// Owns the menu bar items and wires them to the timers and settings.
final class MenuBarCoordinator: NSObject, PresetStatusItemDelegate {
    private let settings: AppSettings
    private let notifications: NotificationManager

    /// One countdown per preset slot, so timers run independently.
    private let engines: [TimerEngine]

    private var items: [PresetStatusItem] = []
    private var settingsWindow: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings = .shared,
        notifications: NotificationManager = .shared
    ) {
        self.settings = settings
        self.notifications = notifications
        self.engines = (0..<AppSettings.slotCount).map { _ in TimerEngine() }
        super.init()

        for (slot, engine) in engines.enumerated() {
            engine.onChange = { [weak self] in self?.refreshDisplays() }
            engine.onFinish = { [weak self] in self?.handleFinish(slot: slot) }
        }

        notifications.onRestartRequest = { [weak self] slot in self?.start(slot: slot) }

        // @Published fires in `willSet`, so hop to the next main-queue turn to
        // read committed values.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    func start() {
        refresh()
    }

    private func engine(forSlot slot: Int) -> TimerEngine? {
        engines.indices.contains(slot) ? engines[slot] : nil
    }

    // MARK: - Menu bar items

    /// Rebuilds the menu bar items so their count matches `visibleCount`.
    ///
    /// macOS inserts each new status item to the *left* of the existing ones,
    /// so the slots are created back-to-front to make slot 1 the leftmost item.
    /// Rebuilding is cheap and only happens when the count actually changes;
    /// each item's `autosaveName` restores any position the user dragged it to.
    private func refresh() {
        let desired = min(AppSettings.slotCount, max(1, settings.visibleCount))

        guard desired != items.count else {
            refreshDisplays()
            return
        }

        // A countdown whose slot is being hidden would have nowhere to display.
        for slot in desired..<AppSettings.slotCount where engines[slot].isActive {
            engines[slot].stop()
        }

        for item in items {
            item.dispose()
        }
        items = (0..<desired)
            .reversed()
            .map { PresetStatusItem(slot: $0, delegate: self) }

        refreshDisplays()
    }

    private func refreshDisplays() {
        for item in items {
            item.apply(appearance(forSlot: item.slot))
        }
    }

    private func appearance(forSlot slot: Int) -> PresetStatusItem.Appearance {
        guard let preset = settings.preset(at: slot), let engine = engine(forSlot: slot) else {
            return .init(kind: .idle, title: "--", symbolName: nil, usesMonospacedDigits: false,
                         isDimmed: false, tooltip: "BarTimer")
        }

        guard engine.isActive else {
            let tooltip = preset.isRunnable
                ? "Start the \(preset.durationDescription) timer\nRight-click for options"
                : "\(preset.displayName) has no duration — right-click to set one"
            return .init(
                kind: preset.isRunnable ? .idle : .needsDuration,
                title: preset.displayName,
                symbolName: preset.isRunnable ? nil : "exclamationmark.triangle",
                usesMonospacedDigits: false,
                isDimmed: false,
                tooltip: tooltip
            )
        }

        switch engine.phase {
        case .running:
            return .init(
                kind: .running,
                title: formatCountdown(engine.remainingSeconds),
                symbolName: nil,
                usesMonospacedDigits: true,
                isDimmed: false,
                tooltip: "\(preset.displayName) timer — \(formatCountdown(engine.remainingSeconds)) left\nClick to pause"
            )
        case .paused:
            // Same title, same font, no glyph: identical width to `.running`, so
            // pausing dims in place instead of shoving the menu bar around.
            return .init(
                kind: .paused,
                title: formatCountdown(engine.remainingSeconds),
                symbolName: nil,
                usesMonospacedDigits: true,
                isDimmed: true,
                tooltip: "\(preset.displayName) timer paused — \(formatCountdown(engine.remainingSeconds)) left\nClick to resume"
            )
        case .finished:
            return .init(
                kind: .finished,
                title: "Done",
                symbolName: "bell.fill",
                usesMonospacedDigits: false,
                isDimmed: false,
                tooltip: "\(preset.displayName) timer finished\nClick to dismiss"
            )
        case .idle:
            return .init(
                kind: .idle,
                title: preset.displayName,
                symbolName: nil,
                usesMonospacedDigits: false,
                isDimmed: false,
                tooltip: "Start the \(preset.durationDescription) timer"
            )
        }
    }

    // MARK: - Actions

    private func start(slot: Int) {
        guard let preset = settings.preset(at: slot), let engine = engine(forSlot: slot) else { return }
        guard preset.isRunnable else {
            openSettings()
            return
        }
        engine.start(duration: preset.duration)
    }

    private func handleFinish(slot: Int) {
        guard let preset = settings.preset(at: slot) else { return }
        notifications.notifyFinished(preset: preset, slot: slot, playSound: settings.playSound)
    }

    // MARK: - PresetStatusItemDelegate

    func statusItem(_ item: PresetStatusItem, wasClickedInSlot slot: Int) {
        guard let engine = engine(forSlot: slot) else { return }

        switch engine.phase {
        case .running, .paused:
            engine.togglePause()
        case .finished:
            engine.dismissFinished()
        case .idle:
            start(slot: slot)
        }
    }

    func contextMenu(forSlot slot: Int) -> NSMenu {
        let menu = NSMenu()
        guard let preset = settings.preset(at: slot), let engine = engine(forSlot: slot) else { return menu }

        menu.addItem(.sectionHeader(title: preset.displayName))

        switch engine.phase {
        case .running, .paused:
            menu.addItem(item(title: engine.isPaused ? "Resume" : "Pause", action: #selector(togglePause), slot: slot))
            menu.addItem(item(title: "Restart", action: #selector(startTimer), slot: slot))
            menu.addItem(item(title: "Stop", action: #selector(stopTimer), slot: slot))
            menu.addItem(.separator())
            menu.addItem(item(title: "Add 1 Minute", action: #selector(addOneMinute), slot: slot))
            menu.addItem(item(title: "Add 5 Minutes", action: #selector(addFiveMinutes), slot: slot))
        case .finished:
            menu.addItem(item(title: "Start Again", action: #selector(startTimer), slot: slot))
            menu.addItem(item(title: "Dismiss", action: #selector(dismissFinished), slot: slot))
        case .idle:
            if preset.isRunnable {
                menu.addItem(item(title: "Start \(preset.durationDescription)", action: #selector(startTimer), slot: slot))
            } else {
                menu.addItem(item(title: "Set a Duration…", action: #selector(openSettingsAction), slot: slot))
            }
        }

        if engines.contains(where: { $0.isActive }) {
            menu.addItem(.separator())
            menu.addItem(item(title: "Stop All Timers", action: #selector(stopAllTimers), slot: slot))
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "Settings…", action: #selector(openSettingsAction), slot: slot, keyEquivalent: ","))
        menu.addItem(item(title: "About BarTimer", action: #selector(showAbout), slot: slot))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit BarTimer", action: #selector(quit), slot: slot, keyEquivalent: "q"))

        return menu
    }

    private func item(title: String, action: Selector, slot: Int, keyEquivalent: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        menuItem.representedObject = slot
        return menuItem
    }

    private func slot(from sender: Any?) -> Int? {
        (sender as? NSMenuItem)?.representedObject as? Int
    }

    // MARK: - Menu selectors

    @objc private func startTimer(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        start(slot: slot)
    }

    @objc private func togglePause(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        engine(forSlot: slot)?.togglePause()
    }

    @objc private func stopTimer(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        engine(forSlot: slot)?.stop()
    }

    @objc private func stopAllTimers(_ sender: Any?) {
        for engine in engines where engine.isActive {
            engine.stop()
        }
    }

    @objc private func dismissFinished(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        engine(forSlot: slot)?.dismissFinished()
    }

    @objc private func addOneMinute(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        engine(forSlot: slot)?.extend(by: 60)
    }

    @objc private func addFiveMinutes(_ sender: Any?) {
        guard let slot = slot(from: sender) else { return }
        engine(forSlot: slot)?.extend(by: 300)
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Settings window

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
        }
        settingsWindow?.show()
    }
}
