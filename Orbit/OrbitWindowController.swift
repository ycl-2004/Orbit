//
//  OrbitWindowController.swift
//  Orbit
//

import AppKit
import SwiftUI

private final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OrbitWindowController: NSObject {
    static let shared = OrbitWindowController()

    private var panel: OrbitPanel?
    private var model: OrbitRingViewModel?
    private var notificationTokens: [NSObjectProtocol] = []

    private override init() {
        super.init()

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .orbitTriggerReleased,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.confirmTriggerRelease()
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .orbitKeyboardCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawCommand = notification.userInfo?["command"] as? String
                let value = notification.userInfo?["value"] as? String
                Task { @MainActor [weak self] in
                    self?.handleKeyboardCommand(rawCommand: rawCommand, value: value)
                }
            }
        )
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func show(at location: CGPoint) {
        // Tear down any stale panel without reporting a close: the ring is
        // being opened right now, and telling the hotkey service otherwise
        // would switch key handling straight back off.
        tearDownPanel()

        // Capture the real frontmost app before the Orbit panel enters the
        // window list. This prevents Orbit from excluding the wrong app. Whether
        // it actually gets excluded is decided in RunningAppCatalog, which already
        // has the window table in hand.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = RunningAppCatalog.shared.collect(frontmostProcess: frontmostPID)

        // 一次唤出只挑一次屏幕，尺寸和摆放共用它。以前尺寸问 `NSScreen.main`、
        // 摆放问光标所在屏，双屏时两者根本不是同一块。
        let targetScreen = screen(containing: location)

        // 开着「唤出即选中最近应用」时，按住再松开就等价于 ⌘Tab。
        let preselecting = OrbitConfig.preselectRecentApp
            ? RunningAppCatalog.mostRecentlyUsed(in: apps, rank: AppActivationHistory.shared.rank(of:))?.id
            : nil

        let ringModel = OrbitRingViewModel(
            apps: apps,
            screen: targetScreen,
            preselecting: preselecting
        )

        ringModel.onCancel = { [weak self] in
            self?.dismissImmediately()
        }
        ringModel.onActivate = { [weak self] app, windowTitle in
            self?.activate(app, windowTitle: windowTitle)
        }

        model = ringModel
        panel = makePanel(at: anchor(for: location, on: targetScreen), model: ringModel, on: targetScreen)
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func dismissImmediately() {
        tearDownPanel()

        // Stop swallowing keys the moment the ring is gone, and drop the
        // captured window contents with it.
        HotKeyService.shared.orbitDidClose()
        WindowPreviewService.shared.flushCache()
    }

    private func tearDownPanel() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private func confirmTriggerRelease() {
        guard let model else {
            dismissImmediately()
            return
        }
        model.triggerReleased()
    }

    private func handleKeyboardCommand(rawCommand: String?, value: String?) {
        guard let model,
              let rawCommand,
              let command = OrbitKeyboardCommand(rawValue: rawCommand) else { return }
        model.handle(command, value: value)
    }

    private func activate(_ app: AppRecord, windowTitle: String?) {
        dismissImmediately()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = app.bringToFront()

            // Raising has to follow activation, or the app pulls its own
            // frontmost window forward again.
            guard let windowTitle else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                _ = WindowPreviewService.raise(
                    windowTitled: windowTitle,
                    pid: app.processIdentifier
                )
            }
        }
    }

    private func makePanel(at location: CGPoint, model: OrbitRingViewModel, on screen: NSScreen?) -> OrbitPanel {
        // The panel grows with the number of cards, and again when the preview
        // panel is enabled, so ask the model for it.
        let size = model.panelSize
        let frame = frame(for: size, centeredAt: location, on: screen)
        let panel = OrbitPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: OrbitRingView(model: model))
        return panel
    }

    /// The cursor only selects which screen the ring belongs to; whether the
    /// ring then follows the cursor or snaps to that screen's center is a
    /// user preference.
    private func anchor(for cursorLocation: CGPoint, on screen: NSScreen?) -> CGPoint {
        switch OrbitConfig.ringPlacement {
        case .cursor:
            return cursorLocation
        case .screenCenter:
            guard let visibleFrame = screen?.visibleFrame else {
                return cursorLocation
            }
            return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
    }

    private func screen(containing location: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main
    }

    private func frame(for size: CGSize, centeredAt location: CGPoint, on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let minimumX = visibleFrame.minX + 8
        let maximumX = max(minimumX, visibleFrame.maxX - size.width - 8)
        let minimumY = visibleFrame.minY + 8
        let maximumY = max(minimumY, visibleFrame.maxY - size.height - 8)

        return NSRect(
            x: min(max(location.x - size.width / 2, minimumX), maximumX),
            y: min(max(location.y - size.height / 2, minimumY), maximumY),
            width: size.width,
            height: size.height
        )
    }
}
