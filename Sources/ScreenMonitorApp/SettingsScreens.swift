import SwiftUI
import UsageHistoryCore
import UsageHistoryUI

/// A settings row whose control is locked behind Pro.
private struct ProRow<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        LabeledContent {
            content().disabled(!model.pro.isPro)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if !model.pro.isPro { ProBadge() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !model.pro.isPro { model.paywallPresented = true } }
    }
}

/// Number field with a unit, clamped to `range`.
private struct NumberField<Value: BinaryInteger>: View {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { Int(value) },
                                         set: { value = Value(clamping: $0).clamped(to: range) }),
                      format: .number)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Break reminders", isOn: $model.storedSettings.reminderEnabled)
                ProRow(title: "Work for") {
                    NumberField(value: $model.storedSettings.workMinutes, range: 1...240, unit: "min")
                }
                ProRow(title: "Break for") {
                    HStack(spacing: 12) {
                        NumberField(value: $model.storedSettings.breakMinutes, range: 0...60, unit: "min")
                        NumberField(value: $model.storedSettings.breakSeconds, range: 0...59, unit: "sec")
                    }
                }
                ProRow(title: "If I keep working, remind me every") {
                    NumberField(value: $model.storedSettings.repeatIntervalMinutes, range: 1...120, unit: "min")
                }
                Toggle("Warn me 1 minute before", isOn: $model.storedSettings.preBreakNotice)
                Toggle("Play a sound when the break ends", isOn: $model.storedSettings.playSoundWhenBreakEnds)
            } header: {
                Text("Breaks")
            } footer: {
                Text("Fatigue reaches 100% after the work time and goes back to 0% after a full break.")
            }

            Section("Break screen") {
                Picker("Style", selection: $model.storedSettings.reminderStyle) {
                    ForEach(ReminderStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Skipping", selection: $model.storedSettings.skipMode) {
                    Text("Allowed").tag(SkipMode.button)
                    Text("Solve a math problem first").tag(SkipMode.challenge)
                    Text("Not allowed").tag(SkipMode.disallowed)
                }
                ProRow(title: "Message") {
                    TextField("", text: $model.storedSettings.popupText, prompt: Text(AppSettings.defaultPopupText))
                        .labelsHidden()
                        .frame(maxWidth: 220)
                }
                ProRow(title: "Background") {
                    HStack(spacing: 8) {
                        ForEach(PopupBackground.allCases) { background in
                            let selected = model.settings.popupBackground == background
                            Circle()
                                .fill(background.style)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary.opacity(selected ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3))
                                .onTapGesture { model.storedSettings.popupBackground = background }
                                .accessibilityLabel(background.rawValue.capitalized)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                ProRow(title: "Show today's screen time") {
                    Toggle("", isOn: $model.storedSettings.showScreenTimeOnPopup).toggleStyle(.switch).labelsHidden()
                }
                LabeledContent("") {
                    Button("Preview") { model.startBreak() }
                        .disabled(model.activeBreak != nil)
                }
            }

            Section {
                ProRow(title: "Remind me about screen time") {
                    Toggle("", isOn: $model.storedSettings.screenTimeReminderEnabled).toggleStyle(.switch).labelsHidden()
                }
                if model.settings.screenTimeReminderEnabled {
                    ForEach(model.storedSettings.screenTimeReminderHours.indices, id: \.self) { index in
                        LabeledContent(index == 0 ? "First reminder at" : "Second reminder at") {
                            HStack(spacing: 6) {
                                TextField("", value: $model.storedSettings.screenTimeReminderHours[index],
                                          format: .number)
                                    .frame(width: 48)
                                    .multilineTextAlignment(.trailing)
                                    .labelsHidden()
                                Text("hours").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Screen time limit")
            }

            Section {
                Picker("Count as resting after", selection: $model.storedSettings.idleThresholdSeconds) {
                    Text("30 seconds idle").tag(30)
                    Text("1 minute idle").tag(60)
                    Text("2 minutes idle").tag(120)
                    Text("5 minutes idle").tag(300)
                }
                LabeledContent("Right now") {
                    Text(model.activeBreak != nil ? "On a break" : model.isUsing ? "In use" : "Resting")
                }
            } header: {
                Text("Activity detection")
            } footer: {
                Text("Keyboard, mouse and trackpad activity count as use. Keys and cursor positions are never recorded.")
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                      set: { model.launchAtLogin = $0 }))
                Toggle("Show fatigue in menu bar", isOn: $model.storedSettings.showFatigueInStatusBar)
                ProRow(title: "Show screen time in menu bar") {
                    Toggle("", isOn: $model.storedSettings.showScreenTimeInStatusBar).toggleStyle(.switch).labelsHidden()
                }
                Toggle("Show in Dock", isOn: $model.storedSettings.showDockIcon)
            }

            if !ProStore.unlockedForEveryone {
                Section("Pro") {
                    LabeledContent("Status", value: model.pro.isPro ? "Pro" : "Free")
                    Button("Restore purchases") { Task { await model.pro.restore() } }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Monitor Pro").font(.title2.weight(.bold))
            ForEach(ProFeature.allCases) { feature in
                Label(feature.title, systemImage: feature.systemImage)
            }
            if let message = model.pro.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Restore purchases") { Task { await model.pro.restore() } }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !model.pro.isPro {
                    Button {
                        Task {
                            await model.pro.purchase()
                            if model.pro.isPro { dismiss() }
                        }
                    } label: {
                        Text(model.pro.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock Pro")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .disabled(model.pro.isLoading)
        }
        .padding(24)
        .frame(width: 460)
    }
}
