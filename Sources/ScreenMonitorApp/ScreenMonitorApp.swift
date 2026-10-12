import AppKit
import SwiftData
import SwiftUI
import UsageHistory
import UsageHistoryCore
import UsageHistoryUI

@main
struct ScreenMonitorApp: App {
    /// `--demo`: in-memory store pre-filled with 120 days of sample data.
    static let isDemo = CommandLine.arguments.contains("--demo")

    let container: ModelContainer
    @State private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        do {
            container = try ModelContainer(
                for: Schema(UsageStore.schema),
                configurations: ModelConfiguration(isStoredInMemoryOnly: Self.isDemo)
            )
        } catch {
            fatalError("Could not create the usage store: \(error)")
        }
        let store = UsageStore(context: container.mainContext)
        if Self.isDemo {
            DemoData.seed(into: store)
        }
        #if DEBUG
        let proOverride = CommandLine.arguments.contains("--pro")
        #else
        let proOverride = false
        #endif
        let pro = ProStore(developerOverride: proOverride)
        let model = AppModel(store: store, pro: pro)
        _model = State(initialValue: model)
        pro.start()
        model.start()
    }

    var body: some Scene {
        Window("Screen Monitor", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            StatusMenu().environment(model)
        } label: {
            StatusLabel(model: model)
        }
    }
}

/// Title of the status bar item: fatigue and/or screen time.
struct StatusLabel: View {
    let model: AppModel

    var body: some View {
        let settings = model.settings
        let parts = [
            settings.showFatigueInStatusBar ? Format.percent(model.fatigue.fatigue) : nil,
            settings.showScreenTimeInStatusBar ? Format.duration(model.screenTimeToday) : nil,
        ].compactMap { $0 }
        if parts.isEmpty {
            Image(systemName: "display")
        } else {
            Text(parts.joined(separator: " · ")).monospacedDigit()
        }
    }
}

struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Fatigue \(Format.percent(model.fatigue.fatigue)) · Screen time \(Format.duration(model.screenTimeToday))")
        if let until = model.snoozedUntil {
            Text("Snoozed until \(until.formatted(date: .omitted, time: .shortened))")
        }
        Divider()
        Button("Start a break manually") { model.startBreak() }
            .disabled(model.activeBreak != nil)
        Menu("Snooze notifications") {
            Button("30 minutes") { model.snooze(for: 30 * 60) }
            Button("1 hour") { model.snooze(for: 60 * 60) }
            Button("2 hours") { model.snooze(for: 2 * 60 * 60) }
            if model.snoozedUntil != nil {
                Divider()
                Button("Resume reminders") { model.snooze(for: nil) }
            }
        }
        Divider()
        Button("Show main window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Screen Monitor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

enum DemoData {
    /// One sample per minute during working hours, fatigue cycling with breaks.
    @MainActor
    static func seed(into store: UsageStore, days: Int = 120, now: Date = .now,
                     calendar: Calendar = .current) {
        var generator = SystemRandomNumberGenerator()
        let today = calendar.startOfDay(for: now)
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let isWeekend = calendar.isDateInWeekend(day)
            if isWeekend, dayOffset > 0, Bool.random(using: &generator) { continue }
            let startMinute = Int.random(in: (8 * 60)...(10 * 60), using: &generator)
            let endMinute = startMinute + Int.random(in: (isWeekend ? 2 : 6) * 60...(isWeekend ? 4 : 10) * 60,
                                                     using: &generator)
            var model = FatigueModel()
            for minute in startMinute..<min(endMinute, 24 * 60) {
                guard let date = calendar.date(byAdding: .minute, value: minute, to: day), date <= now else { break }
                // Each idle minute counts as rest (-20% at a 5-minute break), so keep them rare.
                let isUsing = Double.random(in: 0...1, using: &generator) < 0.98
                model.advance(by: UsageSample.interval, isActive: isUsing)
                store.record(UsageSample(date: date, fatigue: model.fatigue, isUsing: isUsing))
                // At 100% the user takes a break most of the time, sometimes only after a while.
                if model.isFull, Double.random(in: 0...1, using: &generator) < 0.2 {
                    let completed = Double.random(in: 0...1, using: &generator) < 0.7
                    store.record(BreakEvent(start: date, end: date.addingTimeInterval(completed ? 300 : 20),
                                            completed: completed))
                    if completed { model.completeBreak() }
                }
            }
        }
        try? store.context.save()
    }
}
