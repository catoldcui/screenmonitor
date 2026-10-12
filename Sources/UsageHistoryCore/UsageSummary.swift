import Foundation

/// One recorded measurement. Samples are taken at a fixed interval, so
/// durations are `count × UsageSample.interval`.
public struct UsageSample: Equatable, Sendable {
    public static let interval: TimeInterval = 60

    public var date: Date
    public var fatigue: Double
    public var isUsing: Bool

    public init(date: Date, fatigue: Double, isUsing: Bool) {
        self.date = date
        self.fatigue = fatigue
        self.isUsing = isUsing
    }
}

/// Screen time (time in use) within `range`.
public func screenTime(of samples: [UsageSample], in range: DateRange) -> TimeInterval {
    Double(samples.filter { range.contains($0.date) && $0.isUsing }.count) * UsageSample.interval
}

/// Today's screen time compared with yesterday up to the same time of day,
/// as shown next to "Screen Time Today" (e.g. -44%). Nil when yesterday had none.
public func screenTimeChange(samples: [UsageSample], now: Date,
                             calendar: Calendar = .current) -> Double? {
    let todayStart = calendar.startOfDay(for: now)
    guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart),
          let yesterdaySameTime = calendar.date(byAdding: .day, value: -1, to: now)
    else { return nil }
    let today = screenTime(of: samples, in: DateRange(start: todayStart, end: now))
    let yesterday = screenTime(of: samples, in: DateRange(start: yesterdayStart, end: yesterdaySameTime))
    guard yesterday > 0 else { return nil }
    return today / yesterday - 1
}

/// One bar on the Analysis charts.
public struct AnalysisBucket: Identifiable, Equatable, Sendable {
    public let start: Date
    public let screenTime: TimeInterval
    /// Time spent at 100% fatigue.
    public let fatiguePeakDuration: TimeInterval
    public let breaksCompleted: Int
    public let breaksSkipped: Int

    public var id: Date { start }

    /// Share of breaks that were completed rather than skipped; nil without breaks.
    public var complianceRate: Double? {
        let total = breaksCompleted + breaksSkipped
        return total == 0 ? nil : Double(breaksCompleted) / Double(total)
    }
}

public struct AnalysisReport: Equatable, Sendable {
    public let range: DateRange
    public let granularity: Granularity
    /// Every bucket in the range, including empty ones, in chronological order.
    public let buckets: [AnalysisBucket]

    public var totalScreenTime: TimeInterval { buckets.map(\.screenTime).reduce(0, +) }
    public var totalFatiguePeakDuration: TimeInterval { buckets.map(\.fatiguePeakDuration).reduce(0, +) }

    public var complianceRate: Double? {
        let completed = buckets.map(\.breaksCompleted).reduce(0, +)
        let skipped = buckets.map(\.breaksSkipped).reduce(0, +)
        return completed + skipped == 0 ? nil : Double(completed) / Double(completed + skipped)
    }

    public init(samples: [UsageSample], breaks: [BreakEvent], range: DateRange,
                granularity: Granularity, calendar: Calendar = .current) {
        let component = granularity.component
        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: component, for: date)?.start ?? date
        }

        let samplesByBucket = Dictionary(grouping: samples.filter { range.contains($0.date) }) { bucketStart($0.date) }
        let breaksByBucket = Dictionary(grouping: breaks.filter { range.contains($0.start) }) { bucketStart($0.start) }

        var buckets: [AnalysisBucket] = []
        var cursor = bucketStart(range.start)
        while cursor < range.end {
            let bucketSamples = samplesByBucket[cursor] ?? []
            let bucketBreaks = breaksByBucket[cursor] ?? []
            buckets.append(AnalysisBucket(
                start: cursor,
                screenTime: Double(bucketSamples.filter(\.isUsing).count) * UsageSample.interval,
                fatiguePeakDuration: Double(bucketSamples.filter { $0.fatigue >= 1 }.count) * UsageSample.interval,
                breaksCompleted: bucketBreaks.filter(\.completed).count,
                breaksSkipped: bucketBreaks.filter { !$0.completed }.count
            ))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }

        self.range = range
        self.granularity = granularity
        self.buckets = buckets
    }
}
