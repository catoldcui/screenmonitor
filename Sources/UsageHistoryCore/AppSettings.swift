import Foundation

public enum ReminderStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullScreen
    case mini

    public var id: Self { self }

    public var title: String {
        switch self {
        case .fullScreen: "Full-screen popup"
        case .mini: "Mini popup"
        }
    }
}

/// Preset popup backgrounds.
public enum PopupBackground: String, CaseIterable, Identifiable, Codable, Sendable {
    case dusk, forest, ocean, plum, graphite

    public var id: Self { self }

    /// Top and bottom gradient colors as 0xRRGGBB.
    public var gradient: (UInt32, UInt32) {
        switch self {
        case .dusk: (0x3A1C71, 0xD76D77)
        case .forest: (0x134E5E, 0x71B280)
        case .ocean: (0x1A2980, 0x26D0CE)
        case .plum: (0x42275A, 0x734B6D)
        case .graphite: (0x232526, 0x414345)
        }
    }
}

/// Features that require Pro.
public enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case analysis
    case csvExport
    case customBreakRule
    case reminderInterval
    case popupCustomization
    case screenTimeReminder
    case statusBarScreenTime

    public var id: Self { self }

    public var title: String {
        switch self {
        case .analysis: "Access all charts to analyze your usage trends and break habits"
        case .csvExport: "Download all data as a CSV file"
        case .customBreakRule: "Customize break rules"
        case .reminderInterval: "Choose how often to repeat reminders at 100% fatigue"
        case .popupCustomization: "Customize popup background and text"
        case .screenTimeReminder: "Get reminded when Screen Time reaches your limits"
        case .statusBarScreenTime: "Show Screen Time in the status bar"
        }
    }

    public var systemImage: String {
        switch self {
        case .analysis: "chart.bar.xaxis"
        case .csvExport: "square.and.arrow.down"
        case .customBreakRule: "timer"
        case .reminderInterval: "repeat"
        case .popupCustomization: "paintpalette"
        case .screenTimeReminder: "hourglass"
        case .statusBarScreenTime: "menubar.rectangle"
        }
    }
}

/// Every user preference. Pro-only values are stored as chosen but only take
/// effect through `effective(isPro:)`, so buying Pro restores earlier choices.
public struct AppSettings: Equatable, Codable, Sendable {
    // Schedule
    public var reminderEnabled = true
    public var reminderStyle = ReminderStyle.fullScreen
    public var popupText = AppSettings.defaultPopupText
    public var showScreenTimeOnPopup = false
    public var skipMode = SkipMode.button
    public var popupBackground = PopupBackground.dusk
    public var workMinutes = 60
    public var breakMinutes = 5
    public var breakSeconds = 0
    public var repeatIntervalMinutes = 5
    public var preBreakNotice = true
    public var playSoundWhenBreakEnds = true
    public var screenTimeReminderEnabled = false
    public var screenTimeReminderHours = [8.0, 12.0]

    // Accuracy
    /// Input idle longer than this counts as resting rather than using the computer.
    public var idleThresholdSeconds = 60

    // Settings
    public var showFatigueInStatusBar = true
    public var showScreenTimeInStatusBar = false
    public var showDockIcon = true

    public static let defaultPopupText = "Take a break"

    public init() {}

    /// The settings the app should actually use: Pro-only values fall back to
    /// the free defaults when the user does not have Pro.
    public func effective(isPro: Bool) -> AppSettings {
        guard !isPro else { return self }
        let free = AppSettings()
        var result = self
        result.popupText = free.popupText
        result.showScreenTimeOnPopup = free.showScreenTimeOnPopup
        result.popupBackground = free.popupBackground
        result.workMinutes = free.workMinutes
        result.breakMinutes = free.breakMinutes
        result.breakSeconds = free.breakSeconds
        result.repeatIntervalMinutes = free.repeatIntervalMinutes
        result.screenTimeReminderEnabled = free.screenTimeReminderEnabled
        result.showScreenTimeInStatusBar = free.showScreenTimeInStatusBar
        return result
    }

    public var breakRule: BreakRule {
        BreakRule(workDuration: TimeInterval(max(1, workMinutes) * 60),
                  breakDuration: TimeInterval(max(1, breakMinutes * 60 + breakSeconds)))
    }

    // Tolerate settings saved by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func load<T: Decodable>(_ key: CodingKeys, into value: inout T) {
            if let decoded = try? c.decode(T.self, forKey: key) { value = decoded }
        }
        load(.reminderEnabled, into: &reminderEnabled)
        load(.reminderStyle, into: &reminderStyle)
        load(.popupText, into: &popupText)
        load(.showScreenTimeOnPopup, into: &showScreenTimeOnPopup)
        load(.skipMode, into: &skipMode)
        load(.popupBackground, into: &popupBackground)
        load(.workMinutes, into: &workMinutes)
        load(.breakMinutes, into: &breakMinutes)
        load(.breakSeconds, into: &breakSeconds)
        load(.repeatIntervalMinutes, into: &repeatIntervalMinutes)
        load(.preBreakNotice, into: &preBreakNotice)
        load(.playSoundWhenBreakEnds, into: &playSoundWhenBreakEnds)
        load(.screenTimeReminderEnabled, into: &screenTimeReminderEnabled)
        load(.screenTimeReminderHours, into: &screenTimeReminderHours)
        load(.idleThresholdSeconds, into: &idleThresholdSeconds)
        load(.showFatigueInStatusBar, into: &showFatigueInStatusBar)
        load(.showScreenTimeInStatusBar, into: &showScreenTimeInStatusBar)
        load(.showDockIcon, into: &showDockIcon)
    }
}
