import Foundation

/// "Work for X mins, break for Y mins" — the schedule rule.
public struct BreakRule: Equatable, Codable, Sendable {
    /// Continuous use that takes fatigue from 0% to 100%.
    public var workDuration: TimeInterval
    /// Rest that takes fatigue from 100% back to 0%, and the length of a break.
    public var breakDuration: TimeInterval

    public init(workDuration: TimeInterval, breakDuration: TimeInterval) {
        precondition(workDuration > 0 && breakDuration > 0, "durations must be positive")
        self.workDuration = workDuration
        self.breakDuration = breakDuration
    }

    public static let standard = BreakRule(workDuration: 60 * 60, breakDuration: 5 * 60)
}

/// Fatigue rises linearly while the computer is in use and falls while idle.
public struct FatigueModel: Equatable, Sendable {
    /// 0...1
    public private(set) var fatigue: Double
    public var rule: BreakRule

    public init(fatigue: Double = 0, rule: BreakRule = .standard) {
        self.fatigue = min(1, max(0, fatigue))
        self.rule = rule
    }

    public var isFull: Bool { fatigue >= 1 }

    public mutating func advance(by interval: TimeInterval, isActive: Bool) {
        guard interval > 0 else { return }
        let delta = isActive ? interval / rule.workDuration : -interval / rule.breakDuration
        fatigue = min(1, max(0, fatigue + delta))
    }

    /// A finished break resets fatigue to zero.
    public mutating func completeBreak() {
        fatigue = 0
    }

    /// Time of continuous use left until fatigue reaches 100%.
    public var timeUntilFull: TimeInterval {
        (1 - fatigue) * rule.workDuration
    }
}
