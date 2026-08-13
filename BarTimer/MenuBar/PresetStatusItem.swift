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
            // Sizing the symbol to the label's own point size makes it occupy the
            // same vertical band as the digits, so baseline alignment reads as
            // level. Rendering it any smaller leaves it sitting visibly low.
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            let symbol = image.withSymbolConfiguration(config) ?? image
            symbol.isTemplate = true
            button.image = Self.raised(symbol, by: Self.symbolRise)
        } else {
            button.image = nil
        }

        button.toolTip = appearance.tooltip
        button.setAccessibilityLabel(appearance.tooltip)
    }

    /// How far to raise the symbol so it reads as level with the digits.
    /// Purely optical — increase to nudge it further up, 0 to disable.
    /// 0.5 is one device pixel on a Retina display.
    private static let symbolRise: CGFloat = 0.0

    /// Raises a symbol by `rise` points by padding the bottom of its image, which
    /// shifts the glyph up within the status item's fixed-height button.
    private static func raised(_ symbol: NSImage, by rise: CGFloat) -> NSImage {
        let size = symbol.size
        guard rise > 0, size.width > 0, size.height > 0 else { return symbol }

        let padded = NSImage(
            size: NSSize(width: size.width, height: size.height + rise * 2),
            flipped: false
        ) { _ in
            symbol.draw(in: NSRect(x: 0, y: rise * 2, width: size.width, height: size.height))
            return true
        }
        padded.isTemplate = true
        return padded
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
