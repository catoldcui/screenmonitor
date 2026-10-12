import Foundation
import Testing
@testable import UsageHistoryCore

/// A calendar with a DST transition (US Eastern springs forward 2026-03-08).
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.firstWeekday = 2
    return calendar
}()

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct DateRangeTests {
    @Test func dayIsHalfOpen() {
        let range = DateRange.day(containing: date(2026, 10, 11, 15, 30), calendar: testCalendar)
        #expect(range.start == date(2026, 10, 11))
        #expect(range.end == date(2026, 10, 12))
        #expect(range.contains(date(2026, 10, 11)))
        #expect(range.contains(date(2026, 10, 11, 23, 59)))
        #expect(!range.contains(date(2026, 10, 12)))
        #expect(!range.contains(date(2026, 10, 10, 23, 59)))
    }

    @Test func lastDaysIncludesToday() {
        let range = DateRange.lastDays(7, endingOn: date(2026, 10, 11, 8), calendar: testCalendar)
        #expect(range.start == date(2026, 10, 5))
        #expect(range.end == date(2026, 10, 12))
    }

    @Test func dayAcrossDaylightSavingIsTwentyThreeHours() {
        let range = DateRange.day(containing: date(2026, 3, 8, 12), calendar: testCalendar)
        #expect(range.end.timeIntervalSince(range.start) == 23 * 3600)
    }

    @Test func analysisPeriods() {
        let now = date(2026, 10, 11, 12)
        func range(_ period: AnalysisPeriod, earliest: Date? = nil) -> DateRange {
            period.range(now: now, earliest: earliest, calendar: testCalendar)
        }
        #expect(range(.last7Days).start == date(2026, 10, 5))
        #expect(range(.last28Days).start == date(2026, 9, 14))
        #expect(range(.last90Days).start == date(2026, 7, 14))
        #expect(range(.last12Months) == DateRange(start: date(2025, 11, 1), end: date(2026, 10, 12)))
        #expect(range(.allTime, earliest: date(2025, 3, 2, 9)).start == date(2025, 3, 2))
        #expect(range(.allTime).start == date(2026, 10, 11))
    }
}

struct FatigueModelTests {
    let rule = BreakRule(workDuration: 60 * 60, breakDuration: 5 * 60)

    @Test func risesWhileActiveAndFallsWhileResting() {
        var model = FatigueModel(rule: rule)
        model.advance(by: 30 * 60, isActive: true)
        #expect(abs(model.fatigue - 0.5) < 1e-9)
        #expect(model.timeUntilFull == 30 * 60)
        model.advance(by: 60, isActive: false)
        #expect(abs(model.fatigue - 0.3) < 1e-9)
    }

    @Test func clampsBetweenZeroAndOne() {
        var model = FatigueModel(rule: rule)
        model.advance(by: 3 * 60 * 60, isActive: true)
        #expect(model.fatigue == 1)
        #expect(model.isFull)
        model.advance(by: 60 * 60, isActive: false)
        #expect(model.fatigue == 0)
    }

    @Test func completingABreakResets() {
        var model = FatigueModel(fatigue: 1, rule: rule)
        model.completeBreak()
        #expect(model.fatigue == 0)
    }
}

struct ReminderPolicyTests {
    let start = date(2026, 10, 11, 9)
    let rule = BreakRule(workDuration: 60 * 60, breakDuration: 5 * 60)

    @Test func noticeOnceThenBreakThenRepeatWhileFull() {
        var policy = ReminderPolicy(repeatInterval: 5 * 60)
        var model = FatigueModel(rule: rule)

        model.advance(by: 58 * 60, isActive: true)
        #expect(policy.evaluate(model, isActive: true, now: start) == .none)

        model.advance(by: 60, isActive: true) // 1 minute left
        #expect(policy.evaluate(model, isActive: true, now: start) == .preBreakNotice)
        #expect(policy.evaluate(model, isActive: true, now: start) == .none)

        model.advance(by: 60, isActive: true)
        #expect(policy.evaluate(model, isActive: true, now: start) == .startBreak)
        // Skipped: still at 100%, so remind again only after the interval.
        #expect(policy.evaluate(model, isActive: true, now: start.addingTimeInterval(4 * 60)) == .none)
        #expect(policy.evaluate(model, isActive: true, now: start.addingTimeInterval(5 * 60)) == .startBreak)
    }

    @Test func snoozeAndDisableSuppressReminders() {
        let full = FatigueModel(fatigue: 1, rule: rule)
        var policy = ReminderPolicy(snoozedUntil: start.addingTimeInterval(60))
        #expect(policy.evaluate(full, isActive: true, now: start) == .none)
        #expect(policy.evaluate(full, isActive: true, now: start.addingTimeInterval(60)) == .startBreak)

        var disabled = ReminderPolicy(isEnabled: false)
        #expect(disabled.evaluate(full, isActive: true, now: start) == .none)
    }

    @Test func noticeRearmsAfterRest() {
        var policy = ReminderPolicy()
        var model = FatigueModel(fatigue: 59.5 / 60, rule: rule)
        #expect(policy.evaluate(model, isActive: true, now: start) == .preBreakNotice)
        model.completeBreak()
        #expect(policy.evaluate(model, isActive: true, now: start) == .none)
        model.advance(by: 59.5 * 60, isActive: true)
        #expect(policy.evaluate(model, isActive: true, now: start) == .preBreakNotice)
    }

    @Test func noNoticeWhileIdle() {
        var policy = ReminderPolicy()
        let model = FatigueModel(fatigue: 59.5 / 60, rule: rule)
        #expect(policy.evaluate(model, isActive: false, now: start) == .none)
    }
}

struct BreakTests {
    @Test func arithmeticChallenge() {
        let challenge = ArithmeticChallenge(lhs: 47, rhs: 18, operation: .subtract)
        #expect(challenge.question == "47 − 18 = ?")
        #expect(challenge.isCorrect(" 29 "))
        #expect(!challenge.isCorrect("30"))
        #expect(!challenge.isCorrect("abc"))
    }

    @Test func randomChallengesAreNeverNegative() {
        for _ in 0..<500 {
            #expect(ArithmeticChallenge.random().answer >= 0)
        }
    }

    @Test func screenTimeReminderFiresEachThresholdOncePerDay() {
        var reminder = ScreenTimeReminder(thresholds: [8.0 * 3600, 12.0 * 3600])
        // `check` mutates, so call it outside #expect, which may evaluate its operands twice.
        func check(hours: Double, on day: Date) -> TimeInterval? {
            reminder.check(screenTime: hours * 3600, now: day, calendar: testCalendar)
        }
        let day1 = date(2026, 10, 11, 18)
        let results = [check(hours: 7, on: day1), check(hours: 8, on: day1),
                       check(hours: 9, on: day1), check(hours: 13, on: day1)]
        #expect(results == [nil, 8.0 * 3600, nil, 12.0 * 3600])
        let nextDay = check(hours: 13, on: date(2026, 10, 12, 18))
        #expect(nextDay == 12.0 * 3600)
    }
}

struct AnalysisTests {
    @Test func screenTimeChangeComparesWithYesterdayAtSameTime() {
        let now = date(2026, 10, 11, 12)
        var samples: [UsageSample] = []
        for minute in 0..<60 { // yesterday 9:00–10:00 in use
            samples.append(UsageSample(date: date(2026, 10, 10, 9, minute), fatigue: 0.1, isUsing: true))
        }
        for minute in 0..<60 { // yesterday afternoon, after "now" — ignored
            samples.append(UsageSample(date: date(2026, 10, 10, 15, minute), fatigue: 0.1, isUsing: true))
        }
        for minute in 0..<30 { // today 9:00–9:30
            samples.append(UsageSample(date: date(2026, 10, 11, 9, minute), fatigue: 0.1, isUsing: true))
        }
        let change = screenTimeChange(samples: samples, now: now, calendar: testCalendar)
        #expect(change.map { abs($0 + 0.5) < 1e-9 } == true)
        #expect(screenTimeChange(samples: [], now: now, calendar: testCalendar) == nil)
    }

    @Test func dailyReportIncludesEmptyDaysAndMetrics() {
        let range = DateRange.lastDays(3, endingOn: date(2026, 10, 11, 12), calendar: testCalendar)
        let samples = [
            UsageSample(date: date(2026, 10, 9, 10), fatigue: 1, isUsing: true),
            UsageSample(date: date(2026, 10, 9, 10, 1), fatigue: 0.5, isUsing: false),
            UsageSample(date: date(2026, 10, 11, 10), fatigue: 0.2, isUsing: true),
            UsageSample(date: date(2026, 10, 8, 10), fatigue: 1, isUsing: true), // before range
        ]
        let breaks = [
            BreakEvent(start: date(2026, 10, 9, 11), end: date(2026, 10, 9, 11, 5), completed: true),
            BreakEvent(start: date(2026, 10, 9, 13), end: date(2026, 10, 9, 13), completed: false),
            BreakEvent(start: date(2026, 10, 11, 9), end: date(2026, 10, 11, 9, 5), completed: true),
        ]
        let report = AnalysisReport(samples: samples, breaks: breaks, range: range,
                                    granularity: .daily, calendar: testCalendar)

        #expect(report.buckets.map(\.start) == [date(2026, 10, 9), date(2026, 10, 10), date(2026, 10, 11)])
        #expect(report.buckets.map(\.screenTime) == [60, 0, 60])
        #expect(report.buckets.map(\.fatiguePeakDuration) == [60, 0, 0])
        #expect(report.buckets[0].complianceRate == 0.5)
        #expect(report.buckets[1].complianceRate == nil)
        #expect(report.totalScreenTime == 120)
        #expect(report.complianceRate.map { abs($0 - 2.0 / 3) < 1e-9 } == true)
    }

    @Test func weeklyAndMonthlyBuckets() {
        let range = DateRange(start: date(2026, 9, 1), end: date(2026, 10, 12))
        let samples = [UsageSample(date: date(2026, 9, 30, 10), fatigue: 0.5, isUsing: true)]
        let weekly = AnalysisReport(samples: samples, breaks: [], range: range,
                                    granularity: .weekly, calendar: testCalendar)
        #expect(weekly.buckets.first?.start == date(2026, 8, 31)) // Monday
        #expect(weekly.buckets.count == 6) // weeks starting Aug 31 … Oct 5
        #expect(weekly.buckets.first { $0.start == date(2026, 9, 28) }?.screenTime == 60)

        let monthly = AnalysisReport(samples: samples, breaks: [], range: range,
                                     granularity: .monthly, calendar: testCalendar)
        #expect(monthly.buckets.map(\.start) == [date(2026, 9, 1), date(2026, 10, 1)])
        #expect(monthly.buckets.map(\.screenTime) == [60, 0])
    }
}

struct SettingsAndExportTests {
    @Test func proSettingsFallBackToFreeDefaults() {
        var settings = AppSettings()
        settings.workMinutes = 25
        settings.popupText = "Stand up and stretch"
        settings.screenTimeReminderEnabled = true
        settings.skipMode = .challenge // free setting

        let free = settings.effective(isPro: false)
        #expect(free.workMinutes == 60)
        #expect(free.popupText == AppSettings.defaultPopupText)
        #expect(!free.screenTimeReminderEnabled)
        #expect(free.skipMode == .challenge)
        #expect(settings.effective(isPro: true) == settings)
    }

    @Test func breakRuleFromSettings() {
        var settings = AppSettings()
        settings.workMinutes = 20
        settings.breakMinutes = 0
        settings.breakSeconds = 20
        #expect(settings.breakRule == BreakRule(workDuration: 20 * 60, breakDuration: 20))
    }

    @Test func settingsDecodeMissingKeysAsDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"workMinutes": 45}"#.utf8))
        var expected = AppSettings()
        expected.workMinutes = 45
        #expect(decoded == expected)
    }

    @Test func csv() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(CSVExport.usage([UsageSample(date: start, fatigue: 0.426, isUsing: true)])
                == "date,fatigue_percent,is_using\n1970-01-01T00:00:00Z,43,true\n")
        #expect(CSVExport.breaks([BreakEvent(start: start, end: start.addingTimeInterval(300), completed: false)])
                == "start,end,duration_seconds,completed\n1970-01-01T00:00:00Z,1970-01-01T00:05:00Z,300,false\n")
    }
}
