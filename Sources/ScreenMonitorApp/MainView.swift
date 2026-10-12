import SwiftUI
import UsageHistoryCore
import UsageHistoryUI

enum Tab: String, CaseIterable, Identifiable {
    case today = "Today"
    case history = "History"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .today: "display"
        case .history: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab? = .today

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
            }
            .navigationSplitViewColumnWidth(150)
            .safeAreaInset(edge: .bottom) {
                if !model.pro.isPro {
                    Button("Become a Pro") { model.paywallPresented = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .padding()
                }
            }
        } detail: {
            Group {
                switch tab ?? .today {
                case .today: TodayScreen()
                case .history: HistoryScreen()
                case .settings: SettingsScreen()
                }
            }
            .navigationTitle((tab ?? .today).rawValue)
        }
        .sheet(isPresented: $model.paywallPresented) {
            PaywallView()
        }
        .alert("Something went wrong.", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct TodayScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                HStack(spacing: 12) {
                    StatTile("Screen time today", value: Format.duration(model.screenTimeToday),
                             detail: screenTimeDetail)
                    StatTile("Breaks today", value: "\(model.breaksToday.filter(\.completed).count)",
                             detail: breaksDetail)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fatigue today").font(.headline)
                    TodayFatigueChart(samples: model.todaySamples, day: .day(containing: .now))
                        .frame(height: 150)
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            FatigueRing(fatigue: model.fatigue.fatigue)
                .frame(width: 136, height: 136)
            Text(status)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    model.startBreak()
                } label: {
                    Label("Take a break", systemImage: "cup.and.saucer")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.activeBreak != nil)

                SnoozeMenu()
                    .controlSize(.large)
                    .fixedSize()
            }
        }
    }

    private var status: String {
        if model.activeBreak != nil { return "On a break" }
        if let until = model.snoozedUntil {
            return "Reminders paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if !model.settings.reminderEnabled { return "Break reminders are off" }
        if model.fatigue.isFull { return "Time for a break" }
        if !model.isUsing { return "Resting — fatigue is going down" }
        let minutes = Int((model.fatigue.timeUntilFull / 60).rounded(.up))
        return minutes <= 1 ? "Break in about a minute" : "Break in about \(minutes) min"
    }

    private var screenTimeDetail: String? {
        guard let change = model.screenTimeChange else { return nil }
        let percent = Format.percent(abs(change))
        return change >= 0 ? "\(percent) more than yesterday" : "\(percent) less than yesterday"
    }

    private var breaksDetail: String? {
        let skipped = model.breaksToday.filter { !$0.completed }.count
        return skipped == 0 ? nil : "\(skipped) skipped"
    }
}

/// Pause reminders for a while.
struct SnoozeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("30 minutes") { model.snooze(for: 30 * 60) }
            Button("1 hour") { model.snooze(for: 60 * 60) }
            Button("2 hours") { model.snooze(for: 2 * 60 * 60) }
            if model.snoozedUntil != nil {
                Divider()
                Button("Resume reminders") { model.snooze(for: nil) }
            }
        } label: {
            Label(model.snoozedUntil == nil ? "Snooze" : "Snoozed", systemImage: "moon")
        }
    }
}
