import AppKit
import SwiftUI
import UserNotifications

/// Posts user notifications. `UNUserNotificationCenter` only works inside an
/// app bundle, so unbundled runs (`swift run`) fall back to an on-screen toast.
@MainActor
final class Notifier {
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
    private var toast: NSPanel?

    func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        guard isBundled else {
            showToast(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func showToast(title: String, body: String) {
        toast?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 320, height: 72, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 336, y: screen.maxY - 88))
        }
        panel.orderFrontRegardless()
        toast = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak panel] in
            panel?.close()
            if self?.toast === panel { self?.toast = nil }
        }
    }
}
