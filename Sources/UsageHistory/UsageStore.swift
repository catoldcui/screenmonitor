import Foundation
import SwiftData
import UsageHistoryCore

/// Reads and writes usage history.
///
/// Range queries use `#Predicate { $0.date >= start && $0.date < end }`.
/// The filter runs in the store, so only the requested window is loaded.
@MainActor
public struct UsageStore {
    public static let schema: [any PersistentModel.Type] = [UsageRecord.self, BreakRecord.self]

    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func record(_ sample: UsageSample) {
        context.insert(UsageRecord(sample))
    }

    public func record(_ event: BreakEvent) {
        context.insert(BreakRecord(event))
    }

    public func records(in range: DateRange) throws -> [UsageRecord] {
        // #Predicate can only capture plain values, not key paths into `range`.
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<UsageRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor)
    }

    public func samples(in range: DateRange) throws -> [UsageSample] {
        try records(in: range).map(\.sample)
    }

    public func breaks(in range: DateRange) throws -> [BreakEvent] {
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)]
        )
        return try context.fetch(descriptor).map(\.event)
    }

    public func allSamples() throws -> [UsageSample] {
        try context.fetch(FetchDescriptor<UsageRecord>(sortBy: [SortDescriptor(\.date)])).map(\.sample)
    }

    public func allBreaks() throws -> [BreakEvent] {
        try context.fetch(FetchDescriptor<BreakRecord>(sortBy: [SortDescriptor(\.start)])).map(\.event)
    }

    public func earliestSampleDate() throws -> Date? {
        var descriptor = FetchDescriptor<UsageRecord>(sortBy: [SortDescriptor(\.date)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.date
    }

    public func analysis(for period: AnalysisPeriod, granularity: Granularity,
                         now: Date = .now, calendar: Calendar = .current) throws -> AnalysisReport {
        let range = period.range(now: now, earliest: try earliestSampleDate(), calendar: calendar)
        return AnalysisReport(samples: try samples(in: range), breaks: try breaks(in: range),
                              range: range, granularity: granularity, calendar: calendar)
    }
}
