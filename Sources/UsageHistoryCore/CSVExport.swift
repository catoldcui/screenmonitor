import Foundation

/// "Download all data as csv file".
public enum CSVExport {
    public static func usage(_ samples: [UsageSample]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,fatigue_percent,is_using"]
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            lines.append("\(formatter.string(from: sample.date)),\(Int((sample.fatigue * 100).rounded())),\(sample.isUsing)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func breaks(_ breaks: [BreakEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["start,end,duration_seconds,completed"]
        for event in breaks.sorted(by: { $0.start < $1.start }) {
            let duration = Int(event.end.timeIntervalSince(event.start).rounded())
            lines.append("\(formatter.string(from: event.start)),\(formatter.string(from: event.end)),\(duration),\(event.completed)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
