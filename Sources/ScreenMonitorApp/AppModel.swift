import AppKit
import CoreGraphics
import Observation
import ServiceManagement
import SwiftData
import UsageHistory
import UsageHistoryCore

/// A break currently on screen.
struct ActiveBreak: Equatable {
    let start: Date
    let duration: TimeInterval
    var end: Date { start.addingTimeInterval(duration) }
}

/// Owns the fatigue loop: samples input activity, updates fatigue, records
/// history once a minute and starts breaks according to the reminder policy.
@MainActor
@Observable
final class AppModel {
    static let tickInterval: TimeInterval = 5
    private static let settingsKey = "settings.v1"

    let store: UsageStore
    let pro: ProStore
    let notifier = Notifier()
    @ObservationIgnored private lazy var overlay = BreakOverlayController(model: self)

    /// What the user chose, including Pro values they may not currently have.
    var storedSettings: AppSettings {
        didSet {
            persistSettings()
            applySettings()
        }
    }

    /// What is in effect right now.
    var settings: AppSettings { storedSettings.effective(isPro: pro.isPro) }

    private(set) var fatigue = FatigueModel()
    private(set) var policy = ReminderPolicy()
    private(set) var isUsing = false
    private(set) var activeBreak: ActiveBreak?
    private(set) var todaySamples: [UsageSample] = []
    private(set) var screenTimeToday: TimeInterval = 0
    private(set) var screenTimeChange: Double?
    private(set) var breaksToday: [BreakEvent] = []
    /// Bumped after every write so screens that query the store reload.
    private(set) var dataVersion = 0
    var paywallPresented = false
    var lastError: String?

    @ObservationIgnored private var screenTimeReminder = ScreenTimeReminder(thresholds: [])
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = Date.now
    @ObservationIgnored private var lastSampleAt = Date.now

    init(store: UsageStore, pro: ProStore) {
        self.store = store
        self.pro = pro
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            storedSettings = saved
        } else {
            storedSettings = AppSettings()
        }
        // Resume from the most recent fatigue value so a relaunch doesn't reset it,
        // counting the time since then (app not running) as rest.
        if let last = try? store.samples(in: .day(containing: .now)).last {
            fatigue = FatigueModel(fatigue: last.fatigue, rule: storedSettings.effective(isPro: pro.isPro).breakRule)
            fatigue.advance(by: Date.now.timeIntervalSince(last.date), isActive: false)
        }
    }

    func start() {
        applySettings()
        refreshToday()
        notifier.requestAuthorization()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Loop

    func tick(now: Date = .now) {
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now

        let idle = Self.secondsSinceLastInput()
        // A long gap means the Mac was asleep: count it all as rest.
        let wasAsleep = elapsed > 2 * 60
        isUsing = !wasAsleep && activeBreak == nil && idle < Double(settings.idleThresholdSeconds)

        fatigue.rule = settings.breakRule
        if activeBreak == nil {
            fatigue.advance(by: elapsed, isActive: isUsing)
        }

        if let activeBreak, now >= activeBreak.end {
            finishBreak(completed: true, now: now)
        } else if activeBreak == nil {
            switch policy.evaluate(fatigue, isActive: isUsing, now: now) {
            case .none: break
            case .preBreakNotice:
                notifier.post(title: settings.popupText,
                              body: "\(settings.reminderStyle.title) will show in 1 minute.")
            case .startBreak:
                startBreak(now: now)
            }
        }

        if now.timeIntervalSince(lastSampleAt) >= UsageSample.interval {
            lastSampleAt = now
            store.record(UsageSample(date: now, fatigue: fatigue.fatigue, isUsing: isUsing))
            save()
            refreshToday(now: now)
            checkScreenTimeReminder(now: now)
        }
    }

    // MARK: - Breaks

    func startBreak(now: Date = .now) {
        guard activeBreak == nil else { return }
        policy.breakStarted(at: now)
        activeBreak = ActiveBreak(start: now, duration: settings.breakRule.breakDuration)
        overlay.show(style: settings.reminderStyle)
    }

    /// Skip (completed = false) or finish a break.
    func finishBreak(completed: Bool, now: Date = .now) {
        guard let activeBreak else { return }
        self.activeBreak = nil
        overlay.close()
        store.record(BreakEvent(start: activeBreak.start, end: now, completed: completed))
        save()
        refreshToday(now: now)
        if completed {
            fatigue.completeBreak()
            if settings.playSoundWhenBreakEnds {
                NSSound(named: "Glass")?.play()
            }
            notifier.post(title: "Break is over", body: "Welcome back.")
        }
    }

    func snooze(for interval: TimeInterval?, now: Date = .now) {
        policy.snoozedUntil = interval.map { now.addingTimeInterval($0) }
    }

    var snoozedUntil: Date? {
        policy.isSnoozed(at: .now) ? policy.snoozedUntil : nil
    }

    // MARK: - Data

    func refreshToday(now: Date = .now) {
        do {
            let yesterdayAndToday = DateRange.lastDays(2, endingOn: now)
            let samples = try store.samples(in: yesterdayAndToday)
            let today = DateRange.day(containing: now)
            todaySamples = samples.filter { today.contains($0.date) }
            screenTimeToday = screenTime(of: samples, in: today)
            screenTimeChange = UsageHistoryCore.screenTimeChange(samples: samples, now: now)
            breaksToday = try store.breaks(in: today)
        } catch {
            lastError = "Could not load today's usage: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try store.context.save()
        } catch {
            lastError = "Could not save usage: \(error.localizedDescription)"
        }
        dataVersion += 1
    }

    private func checkScreenTimeReminder(now: Date) {
        guard settings.screenTimeReminderEnabled else { return }
        screenTimeReminder.thresholds = settings.screenTimeReminderHours.map { $0 * 3600 }
        if let crossed = screenTimeReminder.check(screenTime: screenTimeToday, now: now) {
            notifier.post(title: "Screen Time Reminder",
                          body: "You have used the computer for \(Int(crossed / 3600)) hours today.")
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ScreenMonitor-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Usage samples are saved here; breaks are saved next to it as …-breaks.csv."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExport.usage(store.allSamples()).write(to: url, atomically: true, encoding: .utf8)
            let breaksURL = url.deletingPathExtension()
                .appendingPathExtension("breaks").appendingPathExtension("csv")
            try CSVExport.breaks(store.allBreaks()).write(to: breaksURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url, breaksURL])
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Settings

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(storedSettings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func applySettings() {
        policy.isEnabled = settings.reminderEnabled
        policy.preBreakNotice = settings.preBreakNotice
        policy.repeatInterval = TimeInterval(max(1, settings.repeatIntervalMinutes) * 60)
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    /// Opens the paywall when `feature` is locked; returns whether it is available.
    @discardableResult
    func requirePro(_ feature: ProFeature) -> Bool {
        if !pro.isPro { paywallPresented = true }
        return pro.isPro
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login needs the bundled app (scripts/bundle.sh): \(error.localizedDescription)"
            }
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad event. Reading the
    /// combined session state needs no Accessibility permission.
    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
