import Foundation
import SwiftData
import UsageHistoryCore

/// One stored usage sample.
@Model
public final class UsageRecord {
    public var date: Date
    public var fatigue: Double
    public var isUsing: Bool

    public init(date: Date, fatigue: Double, isUsing: Bool) {
        self.date = date
        self.fatigue = fatigue
        self.isUsing = isUsing
    }

    public convenience init(_ sample: UsageSample) {
        self.init(date: sample.date, fatigue: sample.fatigue, isUsing: sample.isUsing)
    }

    public var sample: UsageSample {
        UsageSample(date: date, fatigue: fatigue, isUsing: isUsing)
    }
}

/// One shown break, taken or skipped.
@Model
public final class BreakRecord {
    public var start: Date
    public var end: Date
    public var completed: Bool

    public init(start: Date, end: Date, completed: Bool) {
        self.start = start
        self.end = end
        self.completed = completed
    }

    public convenience init(_ event: BreakEvent) {
        self.init(start: event.start, end: event.end, completed: event.completed)
    }

    public var event: BreakEvent {
        BreakEvent(start: start, end: end, completed: completed)
    }
}
