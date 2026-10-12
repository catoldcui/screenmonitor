import Foundation
import SwiftData
import Testing
import UsageHistoryCore
@testable import UsageHistory

@MainActor
struct UsageStoreTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    /// The container must outlive the store's context, so tests hold on to it.
    func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(UsageStore.schema),
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func fetchesOnlyRecordsInsideHalfOpenRangeSortedByDate() throws {
        let container = try makeContainer()
        let store = UsageStore(context: container.mainContext)
        for sample in [
            UsageSample(date: date(11, 14), fatigue: 0.6, isUsing: true),
            UsageSample(date: date(10, 23, 59), fatigue: 0.9, isUsing: true),
            UsageSample(date: date(11, 0), fatigue: 0.1, isUsing: true),
            UsageSample(date: date(12, 0), fatigue: 1.0, isUsing: true),
            UsageSample(date: date(11, 9), fatigue: 0.3, isUsing: false),
        ] {
            store.record(sample)
        }

        let range = DateRange.day(containing: date(11, 12), calendar: calendar)
        #expect(try store.samples(in: range).map(\.date) == [date(11, 0), date(11, 9), date(11, 14)])
        #expect(try store.earliestSampleDate() == date(10, 23, 59))
    }

    @Test func breaksAndAnalysis() throws {
        let container = try makeContainer()
        let store = UsageStore(context: container.mainContext)
        store.record(UsageSample(date: date(5, 10), fatigue: 1, isUsing: true))
        store.record(UsageSample(date: date(4, 10), fatigue: 0.9, isUsing: true)) // outside 7 days
        store.record(UsageSample(date: date(11, 10), fatigue: 0.4, isUsing: true))
        store.record(BreakEvent(start: date(11, 11), end: date(11, 11, 5), completed: true))
        store.record(BreakEvent(start: date(11, 12), end: date(11, 12), completed: false))
        store.record(BreakEvent(start: date(12, 0), end: date(12, 0, 5), completed: true)) // tomorrow

        let today = DateRange.day(containing: date(11, 12), calendar: calendar)
        #expect(try store.breaks(in: today).map(\.completed) == [true, false])

        let report = try store.analysis(for: .last7Days, granularity: .daily,
                                        now: date(11, 12), calendar: calendar)
        #expect(report.buckets.count == 7)
        #expect(report.totalScreenTime == 2 * UsageSample.interval)
        #expect(report.totalFatiguePeakDuration == UsageSample.interval)
        #expect(report.complianceRate == 0.5)

        let allTime = try store.analysis(for: .allTime, granularity: .daily,
                                         now: date(11, 12), calendar: calendar)
        #expect(allTime.range.start == date(4, 0))
    }
}
