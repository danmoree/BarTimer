//
//  SettingsView.swift
//  BarTimer
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Show in menu bar:", selection: $settings.visibleCount) {
                    Text("1 preset").tag(1)
                    Text("2 presets").tag(2)
                    Text("3 presets").tag(3)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Each preset gets its own menu bar item. Hold ⌘ and drag to rearrange them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Presets") {
                ForEach(0..<AppSettings.slotCount, id: \.self) { slot in
                    PresetRow(
                        slot: slot,
                        preset: $settings.presets[slot],
                        isVisible: settings.isVisible(slot: slot)
                    )
                }
            }

            Section {
                Toggle("Play a sound when a timer ends", isOn: $settings.playSound)
                Toggle("Launch BarTimer at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("How it works") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Click a preset to start its countdown.", systemImage: "cursorarrow.click")
                    Label("Click the running timer to pause or resume.", systemImage: "pause.circle")
                    Label("Right-click any preset for more options.", systemImage: "contextualmenu.and.cursorarrow")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            // Put the toggle back where it was rather than lying about the state.
            launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

/// One editable preset: name plus a minutes/seconds duration.
private struct PresetRow: View {
    let slot: Int
    @Binding var preset: TimerPreset
    let isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Preset \(slot + 1)")
                    .frame(width: 62, alignment: .leading)

                TextField(
                    "Name",
                    text: $preset.title,
                    prompt: Text(preset.autoLabel)
                )
                .textFieldStyle(.roundedBorder)
                // Otherwise the Form hoists "Name" into the row's label column.
                .labelsHidden()
                .frame(width: 110)

                Spacer(minLength: 0)

                DurationStepper(value: minutesBinding, range: 0...999, unit: "min", width: 46)
                DurationStepper(value: secondsBinding, range: 0...59, unit: "sec", width: 38)
            }

            if !isVisible {
                Text("Hidden — increase the menu bar count above to show this preset.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !preset.isRunnable {
                Text("Set a duration of at least one second to use this preset.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .opacity(isVisible ? 1 : 0.55)
    }

    private var totalSeconds: Int { Int(preset.duration.rounded()) }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { totalSeconds / 60 },
            set: { preset.duration = TimeInterval(max(0, $0) * 60 + totalSeconds % 60) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { totalSeconds % 60 },
            set: { preset.duration = TimeInterval((totalSeconds / 60) * 60 + max(0, $0)) }
        )
    }
}

/// A small numeric field with an attached stepper, clamped to `range`.
private struct DurationStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: clamped, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .labelsHidden()
                .frame(width: width)
            Stepper("", value: clamped, in: range)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
        }
    }

    private var clamped: Binding<Int> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, value)) },
            set: { value = min(range.upperBound, max(range.lowerBound, $0)) }
        )
    }
}
