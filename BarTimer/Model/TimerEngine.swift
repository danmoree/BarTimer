//
//  TimerEngine.swift
//  BarTimer
//

import AppKit
import Foundation

/// Drives the single active countdown.
///
/// The countdown is stored as an absolute `endDate` rather than a decrementing
/// counter, so the display can never drift and a timer that spans a sleep/wake
/// cycle still reports the correct remaining time (or fires immediately if it
/// expired while the machine was asleep).
final class TimerEngine {
    enum Phase: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    /// How long the menu bar keeps showing "Done" before falling back to the
    /// preset label, if the user never clicks it.
    private static let finishedDisplayDuration: TimeInterval = 90

    private(set) var phase: Phase = .idle
    /// Which preset slot the current countdown belongs to, if any.
    private(set) var activeSlot: Int?

    /// Called whenever the visible state changes and the menu bar needs redrawing.
    var onChange: (() -> Void)?
    /// Called once when a countdown reaches zero.
    var onFinish: ((Int) -> Void)?

    private var ticker: Timer?
    private var finishedTimer: Timer?
    private var activityToken: NSObjectProtocol?
    private var lastDisplayedSeconds: Int?

    init() {
        // A countdown that expires during sleep should report the moment we wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    // MARK: - Queries

    var isActive: Bool { activeSlot != nil && phase != .idle }

    func isActive(slot: Int) -> Bool { activeSlot == slot && phase != .idle }

    /// Seconds still to run, rounded up so a 5-minute timer reads "5:00" the
    /// instant it starts and "0:01" for the final second.
    var remainingSeconds: Int {
        switch phase {
        case .idle, .finished:
            return 0
        case .running(let endDate):
            return max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        case .paused(let remaining):
            return max(0, Int(ceil(remaining)))
        }
    }

    // MARK: - Control

    func start(slot: Int, duration: TimeInterval) {
        guard duration >= 1 else { return }
        stopTicking()
        activeSlot = slot
        phase = .running(endDate: Date().addingTimeInterval(duration))
        lastDisplayedSeconds = nil
        beginTicking()
        notifyChange()
    }

    func pause() {
        guard case .running(let endDate) = phase else { return }
        stopTicking()
        phase = .paused(remaining: max(0, endDate.timeIntervalSinceNow))
        notifyChange()
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(endDate: Date().addingTimeInterval(remaining))
        beginTicking()
        notifyChange()
    }

    func togglePause() {
        switch phase {
        case .running: pause()
        case .paused: resume()
        default: break
        }
    }

    /// Adds time to a running or paused countdown.
    func extend(by interval: TimeInterval) {
        switch phase {
        case .running(let endDate):
            phase = .running(endDate: endDate.addingTimeInterval(interval))
        case .paused(let remaining):
            phase = .paused(remaining: max(0, remaining + interval))
        default:
            return
        }
        notifyChange()
    }

    func stop() {
        stopTicking()
        activeSlot = nil
        phase = .idle
        notifyChange()
    }

    /// Clears the "Done" state without disturbing a countdown that's still running.
    func dismissFinished() {
        guard phase == .finished else { return }
        stop()
    }

    // MARK: - Ticking

    private func beginTicking() {
        // Keep App Nap from throttling the countdown, but still allow the Mac
        // to sleep on its own schedule.
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Countdown timer running"
            )
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.05
        // .common keeps the countdown updating while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        finishedTimer?.invalidate()
        finishedTimer = nil
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    private func tick() {
        guard case .running(let endDate) = phase else { return }

        if endDate.timeIntervalSinceNow <= 0 {
            finish()
            return
        }

        // Only redraw when the displayed value actually changes.
        let seconds = remainingSeconds
        if seconds != lastDisplayedSeconds {
            lastDisplayedSeconds = seconds
            onChange?()
        }
    }

    private func finish() {
        guard let slot = activeSlot else { return }
        stopTicking()
        phase = .finished
        notifyChange()
        onFinish?(slot)

        let timer = Timer(timeInterval: Self.finishedDisplayDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissFinished()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        finishedTimer = timer
    }

    @objc private func systemDidWake() {
        tick()
    }

    private func notifyChange() {
        lastDisplayedSeconds = remainingSeconds
        onChange?()
    }
}
