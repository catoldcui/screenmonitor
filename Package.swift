// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageHistoryCore", targets: ["UsageHistoryCore"]),
        .library(name: "UsageHistoryUI", targets: ["UsageHistoryUI"]),
        .library(name: "UsageHistory", targets: ["UsageHistory"]),
        .executable(name: "ScreenMonitorApp", targets: ["ScreenMonitorApp"]),
    ],
    targets: [
        // Pure Foundation: date ranges and aggregation. Builds with the Command Line Tools.
        .target(name: "UsageHistoryCore"),
        // SwiftUI + Charts views that only depend on the core value types.
        .target(name: "UsageHistoryUI", dependencies: ["UsageHistoryCore"]),
        // SwiftData persistence. The @Model/#Predicate macros require a full Xcode install.
        .target(name: "UsageHistory", dependencies: ["UsageHistoryCore"]),
        .executableTarget(name: "ScreenMonitorApp", dependencies: ["UsageHistory", "UsageHistoryUI"]),
        .testTarget(name: "UsageHistoryCoreTests", dependencies: ["UsageHistoryCore"]),
        .testTarget(name: "UsageHistoryTests", dependencies: ["UsageHistory"]),
    ]
)
