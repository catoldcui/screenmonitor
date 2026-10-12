import Foundation

/// A half-open interval `[start, end)` of time.
///
/// Charts query history with
/// `date >= start AND date < end`, where `start` is the beginning of a day
/// and `end` is derived with `Calendar.date(byAdding:value:to:)`. Using a
/// half-open range means a sample exactly at midnight belongs to the new day
/// and adjacent ranges never double-count a sample.
public struct DateRange: Equatable, Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        precondition(start <= end, "DateRange start must not be after end")
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }

    /// The calendar day containing `date`.
    public static func day(containing date: Date, calendar: Calendar = .current) -> DateRange {
        lastDays(1, endingOn: date, calendar: calendar)
    }

    /// `days` whole calendar days, ending with (and including) the day containing `date`.
    ///
    /// Day boundaries come from the calendar rather than fixed 86 400-second
    /// offsets, so ranges stay correct across daylight-saving transitions.
    public static func lastDays(_ days: Int, endingOn date: Date, calendar: Calendar = .current) -> DateRange {
        precondition(days > 0, "days must be positive")
        let startOfToday = calendar.startOfDay(for: date)
        guard
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday),
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)
        else {
            preconditionFailure("Calendar could not compute day boundaries for \(date)")
        }
        return DateRange(start: start, end: end)
    }
}

/// The ranges offered on the History screen.
public enum AnalysisPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case last7Days
    case last28Days
    case last90Days
    case last12Months
    case allTime

    public var id: Self { self }

    public var title: String {
        switch self {
        case .last7Days: "Last 7 days"
        case .last28Days: "Last 28 days"
        case .last90Days: "Last 90 days"
        case .last12Months: "Last 12 months"
        case .allTime: "All time"
        }
    }

    /// `earliest` is the oldest recorded date; it bounds `.allTime`.
    public func range(now: Date = .now, earliest: Date?, calendar: Calendar = .current) -> DateRange {
        switch self {
        case .last7Days:
            return .lastDays(7, endingOn: now, calendar: calendar)
        case .last28Days:
            return .lastDays(28, endingOn: now, calendar: calendar)
        case .last90Days:
            return .lastDays(90, endingOn: now, calendar: calendar)
        case .last12Months:
            let today = DateRange.day(containing: now, calendar: calendar)
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today.start
            let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            return DateRange(start: start, end: today.end)
        case .allTime:
            let today = DateRange.day(containing: now, calendar: calendar)
            let start = earliest.map { min(calendar.startOfDay(for: $0), today.start) } ?? today.start
            return DateRange(start: start, end: today.end)
        }
    }
}

/// Chart bucket size on the History screen.
public enum Granularity: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily
    case weekly
    case monthly

    public var id: Self { self }

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    public var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }
}
