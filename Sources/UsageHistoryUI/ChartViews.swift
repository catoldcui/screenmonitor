import Charts
import SwiftUI
import UsageHistoryCore

public enum Format {
    /// "2h 05m", or "24m" under an hour.
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// Fatigue and rates are stored as 0...1.
    public static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Green while fresh, orange when tiring, red near a break.
public func fatigueColor(_ fatigue: Double) -> Color {
    switch fatigue {
    case ..<0.6: .green
    case ..<0.9: .orange
    default: .red
    }
}

/// Large ring showing fatigue with the percentage in the middle.
public struct FatigueRing: View {
    let fatigue: Double

    public init(fatigue: Double) {
        self.fatigue = fatigue
    }

    public var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 12)
            Circle()
                .trim(from: 0, to: fatigue)
                .stroke(fatigueColor(fatigue).gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fatigue > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: fatigue)
            VStack(spacing: 0) {
                Text(Format.percent(fatigue))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("fatigue").font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fatigue \(Format.percent(fatigue))")
    }
}

/// Compact labelled number.
public struct StatTile: View {
    let title: String
    let value: String
    let detail: String?

    public init(_ title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Fatigue over one day, x axis 0–24 h.
public struct TodayFatigueChart: View {
    let samples: [UsageSample]
    let day: DateRange

    public init(samples: [UsageSample], day: DateRange) {
        self.samples = samples
        self.day = day
    }

    public var body: some View {
        Chart(samples, id: \.date) { sample in
            AreaMark(x: .value("Time", sample.date), y: .value("Fatigue", sample.fatigue))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", sample.date), y: .value("Fatigue", sample.fatigue))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXScale(domain: day.start...day.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour())
                    }
                }
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { Text(Format.percent(value.as(Double.self) ?? 0)) }
            }
        }
        .overlay {
            if samples.isEmpty {
                Text("Your fatigue over the day will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One History metric drawn as bars over the report's buckets.
public struct AnalysisBarChart: View {
    public enum Metric: String, CaseIterable, Identifiable, Sendable {
        case screenTime = "Screen time"
        case fatiguePeakDuration = "Time at 100%"
        case complianceRate = "Breaks taken"

        public var id: Self { self }

        public var explanation: String {
            switch self {
            case .screenTime: "How long the computer was in use."
            case .fatiguePeakDuration: "How long you kept working with fatigue at 100%."
            case .complianceRate: "Share of breaks you took instead of skipping."
            }
        }
    }

    let report: AnalysisReport
    let metric: Metric

    public init(report: AnalysisReport, metric: Metric) {
        self.report = report
        self.metric = metric
    }

    public var body: some View {
        Chart(report.buckets) { bucket in
            if let y = value(for: bucket) {
                BarMark(x: .value("Date", bucket.start, unit: report.granularity.component),
                        y: .value(metric.rawValue, y))
                    .cornerRadius(4)
                    .foregroundStyle(Color.accentColor.gradient)
            }
        }
        .chartYScale(domain: metric == .complianceRate ? 0...1 : 0...maxValue)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { Text(label(value.as(Double.self) ?? 0)) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisValueLabel()
            }
        }
    }

    private func value(for bucket: AnalysisBucket) -> Double? {
        switch metric {
        case .screenTime: bucket.screenTime / 3600
        case .fatiguePeakDuration: bucket.fatiguePeakDuration / 60
        case .complianceRate: bucket.complianceRate
        }
    }

    private var maxValue: Double {
        max(1, report.buckets.compactMap(value(for:)).max() ?? 1)
    }

    private func label(_ value: Double) -> String {
        switch metric {
        case .screenTime: "\(value.formatted(.number.precision(.fractionLength(0...1))))h"
        case .fatiguePeakDuration: "\(Int(value))m"
        case .complianceRate: Format.percent(value)
        }
    }
}

/// The "PRO" tag shown next to locked settings.
public struct ProBadge: View {
    public init() {}

    public var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(.purple.gradient, in: Capsule())
    }
}
