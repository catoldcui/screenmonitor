import Foundation

public enum ReminderAction: Equatable, Sendable {
    case none
    /// "Show a notification 1 min before the reminder pops up".
    case preBreakNotice
    case startBreak
}

/// Decides when to warn about and start a break, given the current fatigue.
public struct ReminderPolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var preBreakNotice: Bool
    public static let preBreakLeadTime: TimeInterval = 60
    /// "Remind me every N mins if fatigue value remains at 100%".
    public var repeatInterval: TimeInterval
    public var snoozedUntil: Date?

    public private(set) var lastReminderAt: Date?
    public private(set) var preNoticeSent = false

    public init(isEnabled: Bool = true, preBreakNotice: Bool = true,
                repeatInterval: TimeInterval = 5 * 60, snoozedUntil: Date? = nil) {
        self.isEnabled = isEnabled
        self.preBreakNotice = preBreakNotice
        self.repeatInterval = repeatInterval
        self.snoozedUntil = snoozedUntil
    }

    public func isSnoozed(at now: Date) -> Bool {
        snoozedUntil.map { now < $0 } ?? false
    }

    public mutating func evaluate(_ model: FatigueModel, isActive: Bool, now: Date) -> ReminderAction {
        if !model.isFull {
            lastReminderAt = nil
        }
        // Re-arm the notice once fatigue has dropped clearly below the warning point.
        if model.timeUntilFull > Self.preBreakLeadTime * 2 {
            preNoticeSent = false
        }

        guard isEnabled, !isSnoozed(at: now) else { return .none }

        if model.isFull {
            if let last = lastReminderAt, now.timeIntervalSince(last) < repeatInterval {
                return .none
            }
            lastReminderAt = now
            return .startBreak
        }

        if preBreakNotice, isActive, !preNoticeSent, model.timeUntilFull <= Self.preBreakLeadTime {
            preNoticeSent = true
            return .preBreakNotice
        }
        return .none
    }

    /// Call when a break starts for any reason (manual or automatic).
    public mutating func breakStarted(at now: Date) {
        lastReminderAt = now
        preNoticeSent = true
    }
}
