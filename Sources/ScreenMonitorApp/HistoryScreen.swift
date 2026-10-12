import SwiftUI
import UsageHistoryCore
import UsageHistoryUI

struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var period: AnalysisPeriod = .last7Days
    @State private var metric: AnalysisBarChart.Metric = .screenTime
    @State private var report: AnalysisReport?

    private struct Query: Equatable {
        let period: AnalysisPeriod
        let dataVersion: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Period", selection: $period) {
                    ForEach(AnalysisPeriod.allCases) { Text(Self.shortTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let report {
                    summary(report)
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Chart", selection: $metric) {
                            ForEach(AnalysisBarChart.Metric.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 380)
                        Text(metric.explanation).font(.callout).foregroundStyle(.secondary)
                        AnalysisBarChart(report: report, metric: metric).frame(height: 220)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .blur(radius: model.pro.isPro ? 0 : 6)
            .allowsHitTesting(model.pro.isPro)
        }
        .overlay {
            if !model.pro.isPro {
                VStack(spacing: 12) {
                    Text(ProFeature.analysis.title).font(.headline).multilineTextAlignment(.center)
                    Button("Become a Pro") { model.paywallPresented = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .toolbar {
            Button {
                if model.requirePro(.csvExport) { model.exportCSV() }
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .help("Export all data as CSV")
        }
        .task(id: Query(period: period, dataVersion: model.dataVersion)) {
            do {
                report = try model.store.analysis(for: period, granularity: Self.granularity(for: period))
            } catch {
                model.lastError = "Could not load history: \(error.localizedDescription)"
            }
        }
    }

    private func summary(_ report: AnalysisReport) -> some View {
        let days = max(1, report.range.end.timeIntervalSince(report.range.start) / 86_400)
        return HStack(spacing: 12) {
            StatTile("Screen time", value: Format.duration(report.totalScreenTime))
            StatTile("Daily average", value: Format.duration(report.totalScreenTime / days.rounded()))
            StatTile("Time at 100%", value: Format.duration(report.totalFatiguePeakDuration))
            StatTile("Breaks taken", value: report.complianceRate.map(Format.percent) ?? "–")
        }
    }

    /// Bars stay readable: days for short periods, weeks for 90 days, months beyond.
    static func granularity(for period: AnalysisPeriod) -> Granularity {
        switch period {
        case .last7Days, .last28Days: .daily
        case .last90Days: .weekly
        case .last12Months, .allTime: .monthly
        }
    }

    static func shortTitle(_ period: AnalysisPeriod) -> String {
        switch period {
        case .last7Days: "7 days"
        case .last28Days: "28 days"
        case .last90Days: "90 days"
        case .last12Months: "12 months"
        case .allTime: "All time"
        }
    }
}
