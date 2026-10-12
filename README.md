# ScreenMonitor

A macOS break reminder: fatigue rises while you use the computer, and a break
popup appears when it reaches 100%. Includes usage history, analysis charts
and a Pro tier (StoreKit 2). Requires macOS 14+ and Xcode.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points at the CLT
scripts/bundle.sh                       # builds build/ScreenMonitor.app (release)
open build/ScreenMonitor.app               # real use; data persists
open build/ScreenMonitor.app --args --demo # in-memory store with 120 days of sample data
swift test                              # 23 tests
```

Pro is unlocked for everyone (`ProStore.unlockedForEveryone`); set it to false to sell Pro as an in-app purchase.

## Features

| Area | Free | Pro |
|---|---|---|
| Today | Fatigue %, Screen Time Today vs. yesterday, fatigue chart, start break, snooze | |
| Breaks | Full-screen or mini popup, countdown, skip modes (button / arithmetic challenge / cannot skip), notice 1 min before, sound when it ends | Popup text, background, Screen Time on popup; work/break rule; repeat interval at 100% |
| History | | 7/28/90 days, 12 months, all time (grouped by day, week or month automatically); screen time, time at 100%, breaks taken; CSV export |
| Extra reminders | | Screen Time thresholds (default 8 h and 12 h) |
| Status bar / app | Fatigue % in the menu bar, dock icon, launch at login | Screen time in the menu bar |

## Layout

| Target | Contents |
|---|---|
| `UsageHistoryCore` | Pure logic: `FatigueModel`, `ReminderPolicy`, `AnalysisReport`, `ArithmeticChallenge`, `ScreenTimeReminder`, `AppSettings` (with `effective(isPro:)`), CSV export |
| `UsageHistory` | SwiftData `UsageRecord` / `BreakRecord` and `UsageStore` (`date >= start && date < end` queries) |
| `UsageHistoryUI` | Charts and small reusable views |
| `ScreenMonitorApp` | `AppModel` (the 5-second loop), break overlay, notifications, `ProStore`, screens |

Activity comes from the system idle timer (`CGEventSource.secondsSinceLastEventType`),
so no Accessibility permission is needed.

## Before shipping

- Create a non-consumable in-app purchase `com.chenhuicui.screenmonitor.pro` in
  App Store Connect (or a StoreKit configuration file for local testing in Xcode).
- Sign with your team ID; `scripts/bundle.sh` signs ad hoc for local runs only.
- Not implemented: iCloud sync and iPhone reminders (need CloudKit / a push
  server and a paid developer account), global keyboard shortcuts.
