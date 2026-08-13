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
        /// Which state the item is showing. Only a change of `kind` animates —
        /// the countdown ticking from 0:10 to 0:09 must not cross-fade every second.
        enum Kind { case idle, needsDuration, running, paused, finished }

        var kind: Kind
        var title: String
        var symbolName: String?
        var usesMonospacedDigits: Bool
        /// Renders the item in the muted style the status bar uses for inactive
        /// items. Pausing uses this instead of a glyph so the item's width — and
        /// therefore every item to its left — never moves.
        var isDimmed: Bool
        var tooltip: String
    }

    let slot: Int

    /// Long enough to read as a transition, short enough not to lag a click.
    private static let transitionDuration: TimeInterval = 0.18

    /// Opacity of a paused item. Lower is more obviously paused, higher is more
    /// legible at a glance.
    private static let dimmedAlpha: CGFloat = 0.4

    private let statusItem: NSStatusItem
    private weak var delegate: PresetStatusItemDelegate?
    private var currentAppearance: Appearance?
    /// Opacity the item is at, or is animating towards.
    private var alphaTarget: CGFloat = 1
    private var fadeTimer: Timer?

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
            // Composites the opacity changes on the GPU during transitions.
            button.wantsLayer = true
        }
    }

    /// Removes the item from the menu bar. Called explicitly rather than from
    /// `deinit` so teardown stays on the main actor.
    func dispose() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Drawing

    func apply(_ appearance: Appearance) {
        guard appearance != currentAppearance, let button = statusItem.button else { return }

        let previous = currentAppearance
        currentAppearance = appearance

        // Animate between states, but not on every countdown tick — and never on
        // the very first render, which would fade the items in at launch.
        let isStateChange = previous.map { $0.kind != appearance.kind } ?? false
        let contentChanged = previous.map {
            $0.title != appearance.title || $0.symbolName != appearance.symbolName
        } ?? true
        let targetAlpha: CGFloat = appearance.isDimmed ? Self.dimmedAlpha : 1

        guard isStateChange else {
            // A countdown tick: redraw, but leave opacity alone so it cannot cut
            // short a transition that is still running.
            render(appearance, into: button)
            if targetAlpha != alphaTarget {
                alphaTarget = targetAlpha
                button.alphaValue = targetAlpha
            }
            return
        }

        alphaTarget = targetAlpha

        if contentChanged {
            // The label itself changes — a preset becoming a countdown, a countdown
            // becoming "Done". Dip out, swap while invisible, come back up. The
            // width change lands at the invisible point, so it is never seen.
            animateAlpha(button, to: 0, duration: Self.transitionDuration / 2) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.render(appearance, into: button)
                self.animateAlpha(button, to: targetAlpha, duration: Self.transitionDuration / 2)
            }
        } else {
            // Only the styling changes (pause/resume): fade opacity in place.
            render(appearance, into: button)
            animateAlpha(button, to: targetAlpha, duration: Self.transitionDuration)
        }
    }

    /// Interpolates `alphaValue` by hand.
    ///
    /// `button.animator().alphaValue` does not animate a status item's button —
    /// AppKit applies the value instantly — and `CATransition` on its layer does
    /// nothing either, because the button redraws its cell in place rather than
    /// swapping layer contents. Assigning `alphaValue` directly *is* honoured, so
    /// the interpolation is driven here.
    private func animateAlpha(
        _ button: NSStatusBarButton,
        to target: CGFloat,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        fadeTimer?.invalidate()
        fadeTimer = nil

        let start = button.alphaValue
        guard duration > 0, abs(target - start) > 0.001 else {
            button.alphaValue = target
            completion?()
            return
        }

        let began = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak button] timer in
            MainActor.assumeIsolated {
                guard let button else { timer.invalidate(); return }

                let t = min(1, Date().timeIntervalSince(began) / duration)
                let eased = t * t * (3 - 2 * t) // smoothstep
                button.alphaValue = start + (target - start) * eased

                if t >= 1 {
                    timer.invalidate()
                    self?.fadeTimer = nil
                    completion?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func render(_ appearance: Appearance, into button: NSStatusBarButton) {
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
