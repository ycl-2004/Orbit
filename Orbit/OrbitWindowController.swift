//
//  OrbitWindowController.swift
//  Orbit
//

import AppKit
import OSLog
import SwiftUI

private let windowSwitchLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.orbit.local",
    category: "WindowSwitch"
)

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
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApp?.processIdentifier

        // 用户此刻正看着的那扇窗，同样要趁 Orbit 的面板还没进窗口表时问 ——
        // 面板一上屏，最靠前的窗口就成了 Orbit 自己。
        let currentWindow = frontmostPID.flatMap { pid in
            WindowServerInspector.frontWindow(ownedBy: pid).map {
                CurrentWindow(processIdentifier: pid, id: $0)
            }
        }

        // App activation history cannot distinguish two windows owned by the
        // same process. Record the real front window on every summon so a later
        // summon can make the previously viewed sibling the first window target.
        let currentAppID = frontmostApp?.bundleIdentifier
            ?? frontmostApp?.bundleURL?.path
            ?? frontmostPID.map { String($0) }
        if let currentWindow, let currentAppID {
            AppActivationHistory.shared.record(windowID: currentWindow.id, for: currentAppID)
        }
        let recentCurrentAppWindowIDs = currentAppID.map {
            AppActivationHistory.shared.recentWindowIDs(for: $0)
        } ?? []
        let preferredCurrentAppWindow: WindowTarget? = if let currentWindow {
            WindowServerInspector.mostRecentOtherWindow(
                ownedBy: currentWindow.processIdentifier,
                excluding: currentWindow.id,
                preferredIDs: recentCurrentAppWindowIDs
            )
        } else {
            nil
        }

        // A current-app card is useful only when release can name a different
        // window immediately. This prevents a 12-o'clock target that merely
        // reactivates the window already on screen.
        let apps = RunningAppCatalog.shared.collect(
            frontmostProcess: frontmostPID,
            currentAppWindowTargetAvailable: preferredCurrentAppWindow != nil
        )

        // 一次唤出只挑一次屏幕，尺寸和摆放共用它。以前尺寸问 `NSScreen.main`、
        // 摆放问光标所在屏，双屏时两者根本不是同一块。
        let targetScreen = screen(containing: location)

        // Cancel is the safe default. Quick switch is an explicit setting and
        // always selects the same 12-o'clock target that the first arrow enters
        // — the skip-the-Orbit-card rule here is the one `entryCardID` applies.
        let preselecting = OrbitConfig.ringOpeningBehavior == .quickSwitch
            ? (apps.first(where: { !$0.isOrbit }) ?? apps.first)?.id
            : nil

        let ringModel = OrbitRingViewModel(
            apps: apps,
            screen: targetScreen,
            preselecting: preselecting,
            currentWindow: currentWindow,
            recentCurrentAppWindowIDs: recentCurrentAppWindowIDs,
            preferredCurrentAppWindow: preferredCurrentAppWindow
        )

        ringModel.onCancel = { [weak self] in
            self?.dismissImmediately()
        }
        ringModel.onActivate = { [weak self] app, window in
            self?.activate(
                app,
                window: window,
                originatingFrontmostProcess: frontmostPID
            )
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
        model?.resetForDismissal()
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

    private func activate(
        _ app: AppRecord,
        window: WindowTarget?,
        originatingFrontmostProcess: pid_t?
    ) {
        dismissImmediately()

        // Let the ring leave the screen before anything else comes forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window else {
                windowSwitchLogger.notice(
                    "app-only activation pid=\(app.processIdentifier, privacy: .public)"
                )
                _ = app.bringToFront()
                return
            }

            windowSwitchLogger.notice(
                "request pid=\(app.processIdentifier, privacy: .public) target=\(window.id, privacy: .public) origin=\(originatingFrontmostProcess ?? -1, privacy: .public)"
            )

            // Name the window *before* activating the app. macOS follows an
            // application onto the Space its main window lives on, so a window
            // chosen first is a window the switch actually lands on — including
            // the fullscreen windows that each hold a Space of their own.
            //
            // 顺序反过来就是之前那个 bug：先激活应用，系统已经切到"上次那个窗口"
            // 所在的 Space 了，之后再 raise 只是在这个 Space 内部重排，选中的窗
            // 口如果在别的 Space 上就永远到不了。
            let targetWasOnScreen = WindowServerInspector.isWindowOnScreen(
                window.id,
                ownedBy: app.processIdentifier
            )
            let picked = WindowPreviewService.focus(window, pid: app.processIdentifier)
            let directFocusCompletesSwitch = WindowPreviewService.directFocusCanCompleteSwitch(
                focusSucceeded: picked,
                targetWasOnScreen: targetWasOnScreen,
                targetProcess: app.processIdentifier,
                originatingFrontmostProcess: originatingFrontmostProcess
            )
            windowSwitchLogger.notice(
                "direct AX target=\(window.id, privacy: .public) picked=\(picked, privacy: .public) wasOnScreen=\(targetWasOnScreen, privacy: .public) completes=\(directFocusCompletesSwitch, privacy: .public)"
            )

            if directFocusCompletesSwitch {
                // `.activateAllWindows` would restore the app's own
                // front-to-back order, undoing the choice just made.
                _ = app.bringToFront(raisingAllWindows: false)

                // Some apps re-assert their own front window as they come
                // forward. One settle pass after activation catches them.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    WindowPreviewService.focus(window, pid: app.processIdentifier)
                }
                return
            }

            // Accessibility saw no such window — for Chromium-based apps it
            // never sees any. Two fallbacks, the more capable one first:
            //
            // The app's own Window menu (which Chromium *does* expose to
            // Accessibility) performs a real makeKeyAndOrderFront, so it can
            // cross Spaces — a fullscreen window on another Space is exactly
            // the case AppleScript's reorder-only `set index` cannot reach.
            let knownTitles = WindowServerInspector.windowTitles(ownedBy: app.processIdentifier)
            let menuPressed = ScriptedWindowFocus.focusViaWindowMenu(
                window,
                pid: app.processIdentifier,
                knownWindowTitles: knownTitles
            )
            windowSwitchLogger.notice(
                "menu result target=\(window.id, privacy: .public) pressed=\(menuPressed, privacy: .public) known=\(knownTitles.count, privacy: .public)"
            )
            if menuPressed {
                // The Window-menu action is itself the cross-Space operation.
                // If Chrome was already frontmost behind Orbit, activating the
                // process again can restore the old fullscreen window and undo
                // the selection. Only a switch originating in another process
                // needs a follow-up application activation.
                if ScriptedWindowFocus.needsActivationAfterWindowMenu(
                    targetProcess: app.processIdentifier,
                    originatingFrontmostProcess: originatingFrontmostProcess
                ) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let activated = app.bringToFront(raisingAllWindows: false)
                        windowSwitchLogger.notice(
                            "cross-app activation target=\(window.id, privacy: .public) result=\(activated, privacy: .public)"
                        )
                    }
                } else {
                    windowSwitchLogger.notice(
                        "same-app menu switch target=\(window.id, privacy: .public); no reactivation"
                    )
                }
                return
            }

            // Apple Events reorder: right window within the current Space.
            // Only when that too comes back empty-handed does this degrade to
            // plain app activation, the behaviour Orbit always had.
            //
            // 这一步是唯一可能拖很久才回来的：对一个应用首次发 Apple Event 会弹出
            // 系统的自动化授权框，而那个框在屏幕上挂多久，这里就阻塞多久。所以回来
            // 之后要先问一句"这次切换还是用户正在做的事吗"。
            let requestedAt = Date()
            ScriptedWindowFocus.focus(window, bundleIdentifier: app.id) { switched in
                let elapsed = Date().timeIntervalSince(requestedAt)
                windowSwitchLogger.notice(
                    "AppleScript fallback target=\(window.id, privacy: .public) switched=\(switched, privacy: .public) elapsed=\(elapsed, privacy: .public)"
                )
                guard !switched else { return }
                guard ScriptedWindowFocus.fallbackActivationIsStillRelevant(elapsed: elapsed) else {
                    windowSwitchLogger.notice(
                        "stale fallback abandoned target=\(window.id, privacy: .public)"
                    )
                    return
                }
                _ = app.bringToFront()
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
