import AppKit
import SwiftUI
import UsageHistoryCore
import UsageHistoryUI

/// Borderless windows refuse key status by default, which would leave the
/// challenge's answer field unable to receive typing.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows the break popup: a window over every screen, or a small panel.
@MainActor
final class BreakOverlayController {
    private unowned let model: AppModel
    private var windows: [NSWindow] = []

    init(model: AppModel) {
        self.model = model
    }

    func show(style: ReminderStyle) {
        close()
        switch style {
        case .fullScreen:
            for screen in NSScreen.screens {
                let window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false, screen: screen)
                configure(window, level: .screenSaver)
                window.setFrame(screen.frame, display: true)
                window.contentView = NSHostingView(rootView: BreakView(model: model, isFullScreen: true))
                windows.append(window)
            }
        case .mini:
            // Tall enough for the challenge rows when skipping needs an answer.
            let size = NSSize(width: 360, height: 340)
            let window = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            configure(window, level: .floating)
            if let frame = NSScreen.main?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16))
            }
            window.contentView = NSHostingView(rootView: BreakView(model: model, isFullScreen: false))
            windows.append(window)
        }
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func configure(_ window: NSWindow, level: NSWindow.Level) {
        window.level = level
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension PopupBackground {
    var style: LinearGradient {
        LinearGradient(colors: [Color(hex: gradient.0), Color(hex: gradient.1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct BreakView: View {
    let model: AppModel
    let isFullScreen: Bool

    @State private var challenge: ArithmeticChallenge?
    @State private var answer = ""
    @State private var wrongAnswer = false

    var body: some View {
        let settings = model.settings
        ZStack {
            if isFullScreen {
                settings.popupBackground.style.ignoresSafeArea()
            } else {
                RoundedRectangle(cornerRadius: 16).fill(settings.popupBackground.style)
            }
            VStack(spacing: isFullScreen ? 24 : 12) {
                Image(systemName: "display").font(.system(size: isFullScreen ? 56 : 28))
                Text(settings.popupText)
                    .font(.system(size: isFullScreen ? 44 : 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                countdown
                if settings.showScreenTimeOnPopup {
                    Text("Screen time today: \(Format.duration(model.screenTimeToday))")
                        .font(isFullScreen ? .title3 : .callout)
                        .opacity(0.85)
                }
                skipControls(settings.skipMode)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, (model.activeBreak?.end ?? context.date).timeIntervalSince(context.date))
            Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: isFullScreen ? 72 : 34, weight: .light).monospacedDigit())
        }
    }

    @ViewBuilder
    private func skipControls(_ mode: SkipMode) -> some View {
        switch mode {
        case .disallowed:
            Text("Cannot skip").font(.callout).opacity(0.7)
        case .button:
            Button("Skip a break") { model.finishBreak(completed: false) }
                .buttonStyle(.bordered)
        case .challenge:
            if let challenge {
                VStack(spacing: 8) {
                    Text("Arithmetic challenge: \(challenge.question)").font(.headline)
                    HStack {
                        TextField("Enter the answer", text: $answer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onSubmit(submit)
                        Button("Submit answer and skip break", action: submit)
                    }
                    if wrongAnswer {
                        Text("Incorrect answer. Please try again.").font(.callout)
                    }
                    Button("Cancel and continue resting") {
                        self.challenge = nil
                        answer = ""
                        wrongAnswer = false
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.white)
                }
            } else {
                Button("Skip a break") { challenge = .random() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func submit() {
        guard let challenge else { return }
        if challenge.isCorrect(answer) {
            model.finishBreak(completed: false)
        } else {
            wrongAnswer = true
            answer = ""
            self.challenge = .random()
        }
    }
}
