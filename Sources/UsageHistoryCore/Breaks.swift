import Foundation

/// How a break can be skipped.
public enum SkipMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case button
    case challenge
    case disallowed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .button: "Click the skip button"
        case .challenge: "Click the skip button and solve a challenge"
        case .disallowed: "Cannot skip"
        }
    }
}

/// The arithmetic question shown before a break may be skipped.
public struct ArithmeticChallenge: Equatable, Sendable {
    public enum Operation: String, Sendable { case add = "+", subtract = "−", multiply = "×" }

    public let lhs: Int
    public let rhs: Int
    public let operation: Operation

    public init(lhs: Int, rhs: Int, operation: Operation) {
        self.lhs = lhs
        self.rhs = rhs
        self.operation = operation
    }

    public var question: String { "\(lhs) \(operation.rawValue) \(rhs) = ?" }

    public var answer: Int {
        switch operation {
        case .add: lhs + rhs
        case .subtract: lhs - rhs
        case .multiply: lhs * rhs
        }
    }

    public func isCorrect(_ input: String) -> Bool {
        Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) == answer
    }

    /// Hard enough to interrupt autopilot, never negative.
    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> ArithmeticChallenge {
        switch Int.random(in: 0..<3, using: &generator) {
        case 0:
            return .init(lhs: .random(in: 12...99, using: &generator),
                         rhs: .random(in: 12...99, using: &generator), operation: .add)
        case 1:
            let lhs = Int.random(in: 50...199, using: &generator)
            return .init(lhs: lhs, rhs: .random(in: 11...lhs, using: &generator), operation: .subtract)
        default:
            return .init(lhs: .random(in: 6...19, using: &generator),
                         rhs: .random(in: 3...9, using: &generator), operation: .multiply)
        }
    }

    public static func random() -> ArithmeticChallenge {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }
}

/// A break that was shown, and whether the user completed or skipped it.
/// A break that was shown, and whether it was taken.
public struct BreakEvent: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var completed: Bool

    public init(start: Date, end: Date, completed: Bool) {
        self.start = start
        self.end = end
        self.completed = completed
    }
}

/// Fires each configured Screen Time threshold once per day.
public struct ScreenTimeReminder: Equatable, Sendable {
    public var thresholds: [TimeInterval]
    private var firedDay: Date?
    private var fired: Set<TimeInterval> = []

    public init(thresholds: [TimeInterval]) {
        self.thresholds = thresholds
    }

    /// Returns the highest threshold newly crossed today, if any.
    public mutating func check(screenTime: TimeInterval, now: Date,
                               calendar: Calendar = .current) -> TimeInterval? {
        let day = calendar.startOfDay(for: now)
        if firedDay != day {
            firedDay = day
            fired = []
        }
        let crossed = thresholds.filter { $0 > 0 && screenTime >= $0 && !fired.contains($0) }
        fired.formUnion(crossed)
        return crossed.max()
    }
}
