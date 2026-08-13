//
//  PresetStatusItem.swift
//  BarTimer
//

import AppKit

@MainActor
protocol PresetStatusItemDelegate: AnyObject {
    func statusItem(_ item: PresetStatusItem, wasClickedInSlot slot: Int)
    func contextMenu(forSlot slot: Int) -> NSMenu
}

/// One menu bar item, representing one preset slot.
final class PresetStatusItem: NSObject, NSMenuDelegate {
    /// How the item should draw itself right now.
    struct Appearance: Equatable {
        var title: String
        var symbolName: String?
        var usesMonospacedDigits: Bool
        var tooltip: String
    }

    let slot: Int

    private let statusItem: NSStatusItem
    private weak var delegate: PresetStatusItemDelegate?
    private var currentAppearance: Appearance?

    init(slot: Int, delegate: PresetStatusItemDelegate) {
        self.slot = slot
        self.delegate = delegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Lets macOS remember where the user dragged each item.
        statusItem.autosaveName = "BarTimer.slot.\(slot)"

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
    }

    /// Removes the item from the menu bar. Called explicitly rather than from
    /// `deinit` so teardown stays on the main actor.
    func dispose() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Drawing

    func apply(_ appearance: Appearance) {
        guard appearance != currentAppearance, let button = statusItem.button else { return }
        currentAppearance = appearance

        let pointSize = NSFont.menuBarFont(ofSize: 0).pointSize
        // Monospaced digits stop the countdown from jittering the menu bar
        // layout as the numbers change width.
        button.font = appearance.usesMonospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)

        // Plain `title` (not `attributedTitle`) so AppKit keeps handling the
        // light/dark menu bar and the inverted highlight while a menu is open.
        button.title = appearance.title

        if let symbolName = appearance.symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize - 2, weight: .medium)
            let templated = image.withSymbolConfiguration(config) ?? image
            templated.isTemplate = true
            button.image = templated
        } else {
            button.image = nil
        }

        button.toolTip = appearance.tooltip
        button.setAccessibilityLabel(appearance.tooltip)
    }

    // MARK: - Interaction

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondaryClick {
            showMenu()
        } else {
            delegate?.statusItem(self, wasClickedInSlot: slot)
        }
    }

    private func showMenu() {
        guard let menu = delegate?.contextMenu(forSlot: slot) else { return }
        menu.delegate = self
        // Attaching the menu and re-clicking gives the item the standard
        // highlighted-while-open appearance.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detaching immediately would mutate the menu while it's still
        // unwinding its tracking loop.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }
}
