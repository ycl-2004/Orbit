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
    /// 铺满屏幕的暗场，永远排在环下面一层。
    private var scrim: NSPanel?
    private var model: OrbitRingViewModel?
    private var notificationTokens: [NSObjectProtocol] = []

    /// 哪一次收场还算数 —— 跟 `switchGeneration` 同一个道理。
    ///
    /// Cancelling now folds the cards back into the hub before the window goes,
    /// so teardown is deferred by the length of that animation. Re-summoning
    /// inside that window has to invalidate the pending teardown, or it would
    /// close the ring the user has just opened.
    private var dismissGeneration = 0

    /// 哪一次切换还算数。
    ///
    /// A switch no longer finishes inside one turn of the run loop: each step
    /// is followed by up to `switchVerificationTimeout` of polling before it
    /// gives up and falls through to the next one. Two switches in quick
    /// succession therefore overlap, and without this the first one's polling
    /// would notice it is not on its target any more — because the user has
    /// since moved on — and "recover" by dragging them back. Every deferred
    /// step checks that it still belongs to the newest gesture.
    private var switchGeneration = 0

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

        // 圆环一唤出，上一次切换的补救就不再是用户要的东西了 —— 他已经在挑下一个
        // 目的地。让那条还在轮询的降级链就地作废，别在选择的过程中把画面抢走。
        switchGeneration += 1

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
        let preselecting = OrbitPreferences.ringOpeningBehavior == .quickSwitch
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
            self?.dismissCancelled()
        }
        ringModel.onActivate = { [weak self] app, window in
            self?.activate(
                app,
                window: window,
                originatingFrontmostProcess: frontmostPID
            )
        }

        model = ringModel
        let ringPanel = makePanel(
            at: anchor(for: location, on: targetScreen),
            model: ringModel,
            on: targetScreen
        )
        panel = ringPanel

        // 暗场先上，环再压在它上面。
        scrim = makeScrim(for: ringModel, ringFrame: ringPanel.frame, on: targetScreen)
        scrim?.orderFrontRegardless()

        ringPanel.orderFrontRegardless()
        ringPanel.makeKey()
    }

    func dismissImmediately() {
        tearDownPanel()

        // Stop swallowing keys the moment the ring is gone, and drop the
        // captured window contents with it.
        TriggerMonitor.shared.orbitDidClose()
        WindowPreviewService.shared.flushCache()
    }

    /// 取消时让卡片沿着来时的路收回中心，再撤窗口。
    ///
    /// Only this path animates. Confirming a switch tears down at once, because
    /// there the ring would otherwise still be sitting over the app the user has
    /// already chosen — a wait the gesture cannot afford. Cancelling is going
    /// nowhere, so it can afford to put things back where they came from.
    private func dismissCancelled() {
        guard let model, panel != nil, !model.isCollapsing else {
            dismissImmediately()
            return
        }

        model.beginCollapse()
        dismissGeneration += 1
        let generation = dismissGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitPreferences.collapseDuration) { [weak self] in
            guard let self, self.dismissGeneration == generation else { return }
            self.dismissImmediately()
        }
    }

    private func tearDownPanel() {
        // 任何还挂着的收场动画就此作废：窗口已经要走了，或者已经换了一批。
        dismissGeneration += 1
        model?.resetForDismissal()
        panel?.orderOut(nil)
        panel = nil
        scrim?.orderOut(nil)
        scrim = nil
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

    /// 一次窗口切换依次可以走的几条路，能力从强到弱。
    private enum SwitchStage: String {
        case directAX
        case windowMenu
        case appleScript
        case plainActivation
    }

    private func activate(
        _ app: AppRecord,
        window: WindowTarget?,
        originatingFrontmostProcess: pid_t?
    ) {
        dismissImmediately()

        switchGeneration += 1
        let generation = switchGeneration

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
            self.perform(
                .directAX,
                app: app,
                window: window,
                origin: originatingFrontmostProcess,
                generation: generation
            )
        }
    }

    /// 这一步还属于最新的那次切换吗。
    private func isCurrent(_ generation: Int) -> Bool {
        generation == switchGeneration
    }

    /// 走一级切换。
    ///
    /// 每一级只做一件事，然后交给 `verifyLanding` 去问窗口服务这次到底落在哪扇窗
    /// 上；没落到就降到下一级。这个回头确认是必须的，因为每一级返回的都只是「请求
    /// 被接受了」而不是「你到了」：AX 的 raise 对一扇在别的 Space 上、它根本没去成
    /// 的窗口照样报成功，Chromium 的 `set index` 在原地重排一下也报成功。以前这些
    /// 「成功」直接结束整次切换，于是切到了应用、却停在它自己记得的那扇窗上。
    private func perform(
        _ stage: SwitchStage,
        app: AppRecord,
        window: WindowTarget,
        origin: pid_t?,
        generation: Int
    ) {
        guard isCurrent(generation) else {
            windowSwitchLogger.notice(
                "superseded before \(stage.rawValue, privacy: .public) target=\(window.id, privacy: .public)"
            )
            return
        }

        switch stage {
        case .directAX:
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
                originatingFrontmostProcess: origin
            )
            windowSwitchLogger.notice(
                "direct AX target=\(window.id, privacy: .public) picked=\(picked, privacy: .public) wasOnScreen=\(targetWasOnScreen, privacy: .public) completes=\(directFocusCompletesSwitch, privacy: .public)"
            )

            guard directFocusCompletesSwitch else {
                perform(.windowMenu, app: app, window: window, origin: origin, generation: generation)
                return
            }

            // `.activateAllWindows` would restore the app's own front-to-back
            // order, undoing the choice just made — and a reopen would let the
            // app pick a window of its own over the one already named.
            _ = app.bringToFront(raisingAllWindows: false, reopeningWhenWindowless: false)

            // Some apps re-assert their own front window as they come
            // forward. One settle pass after activation catches them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard self?.isCurrent(generation) == true else { return }
                WindowPreviewService.focus(window, pid: app.processIdentifier)
            }
            verifyLanding(
                after: stage,
                app: app,
                window: window,
                origin: origin,
                next: .windowMenu,
                generation: generation
            )

        case .windowMenu:
            // Accessibility saw no such window — for Chromium-based apps it
            // often sees none at all. The app's own Window menu (which Chromium
            // *does* expose to Accessibility) performs a real
            // makeKeyAndOrderFront, so it can cross Spaces — a fullscreen
            // window on another Space is exactly the case AppleScript's
            // reorder-only `set index` cannot reach.
            let knownTitles = WindowServerInspector.windowTitles(ownedBy: app.processIdentifier)
            let menuPressed = ScriptedWindowFocus.focusViaWindowMenu(
                window,
                pid: app.processIdentifier,
                knownWindowTitles: knownTitles
            )
            windowSwitchLogger.notice(
                "menu result target=\(window.id, privacy: .public) pressed=\(menuPressed, privacy: .public) known=\(knownTitles.count, privacy: .public)"
            )
            guard menuPressed else {
                perform(.appleScript, app: app, window: window, origin: origin, generation: generation)
                return
            }

            // The Window-menu action is itself the cross-Space operation. If
            // the app is already frontmost, activating the process again can
            // restore its old fullscreen window and undo the selection. Only a
            // switch that comes from another process needs a follow-up
            // application activation.
            //
            // 问的是「此刻」谁在前台，而不是唤出圆环那一刻谁在前台：这一级也可能
            // 是从上一级降下来的，而上一级已经把目标应用激活过了。
            let frontmostNow = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if ScriptedWindowFocus.needsActivationAfterWindowMenu(
                targetProcess: app.processIdentifier,
                originatingFrontmostProcess: frontmostNow ?? origin
            ) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard self?.isCurrent(generation) == true else { return }
                    let activated = app.bringToFront(
                        raisingAllWindows: false,
                        reopeningWhenWindowless: false
                    )
                    windowSwitchLogger.notice(
                        "cross-app activation target=\(window.id, privacy: .public) result=\(activated, privacy: .public)"
                    )
                }
            } else {
                windowSwitchLogger.notice(
                    "same-app menu switch target=\(window.id, privacy: .public); no reactivation"
                )
            }
            verifyLanding(
                after: stage,
                app: app,
                window: window,
                origin: origin,
                next: .appleScript,
                generation: generation
            )

        case .appleScript:
            // Apple Events reorder: right window within the current Space.
            //
            // 这一步是唯一可能拖很久才回来的：对一个应用首次发 Apple Event 会弹出
            // 系统的自动化授权框，而那个框在屏幕上挂多久，这里就阻塞多久。所以回来
            // 之后要先问一句"这次切换还是用户正在做的事吗"。
            let requestedAt = Date()
            ScriptedWindowFocus.focus(window, bundleIdentifier: app.id) { [weak self] switched in
                let elapsed = Date().timeIntervalSince(requestedAt)
                windowSwitchLogger.notice(
                    "AppleScript fallback target=\(window.id, privacy: .public) switched=\(switched, privacy: .public) elapsed=\(elapsed, privacy: .public)"
                )
                guard ScriptedWindowFocus.fallbackActivationIsStillRelevant(elapsed: elapsed) else {
                    windowSwitchLogger.notice(
                        "stale fallback abandoned target=\(window.id, privacy: .public)"
                    )
                    return
                }
                guard let self else { return }
                guard switched else {
                    self.perform(
                        .plainActivation,
                        app: app,
                        window: window,
                        origin: origin,
                        generation: generation
                    )
                    return
                }
                // `set index` 报的成功只覆盖「找到了同名的窗口并重排了一下」。跨
                // Space 它做不到，而那正是它最常被叫到的场合，所以这里同样要确认。
                self.verifyLanding(
                    after: .appleScript,
                    app: app,
                    window: window,
                    origin: origin,
                    next: .plainActivation,
                    generation: generation
                )
            }

        case .plainActivation:
            // 最后的退路，也是 Orbit 一直以来的行为：把应用整个带到前面，让它自己
            // 决定停在哪扇窗上。到这里说明没有任何一条路能指定窗口了。
            windowSwitchLogger.notice(
                "plain activation target=\(window.id, privacy: .public)"
            )
            _ = app.bringToFront()
        }
    }

    /// 等窗口服务确认这次切换真的落在了目标窗口上；等不到就降到 `next`。
    ///
    /// 轮询而不是只查一次：同一个 Space 内部的切换几乎立刻就到位，而跨到一个全屏
    /// Space 要先跑完一段动画。轮询让前者快、后者也够宽。
    private func verifyLanding(
        after stage: SwitchStage,
        app: AppRecord,
        window: WindowTarget,
        origin: pid_t?,
        next: SwitchStage,
        generation: Int,
        deadline: Date? = nil
    ) {
        let deadline = deadline
            ?? Date().addingTimeInterval(OrbitPreferences.switchVerificationTimeout)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + OrbitPreferences.switchVerificationPollInterval
        ) { [weak self] in
            guard let self, self.isCurrent(generation) else { return }

            if WindowServerInspector.switchLanded(on: window.id, ownedBy: app.processIdentifier) {
                windowSwitchLogger.notice(
                    "landed via \(stage.rawValue, privacy: .public) target=\(window.id, privacy: .public)"
                )
                return
            }
            guard Date() >= deadline else {
                self.verifyLanding(
                    after: stage,
                    app: app,
                    window: window,
                    origin: origin,
                    next: next,
                    generation: generation,
                    deadline: deadline
                )
                return
            }
            windowSwitchLogger.notice(
                "\(stage.rawValue, privacy: .public) did not land target=\(window.id, privacy: .public); falling back to \(next.rawValue, privacy: .public)"
            )
            self.perform(next, app: app, window: window, origin: origin, generation: generation)
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
        panel.appearance = Self.ringAppearance
        // 明确比暗场高一级，而不是靠两个同级窗口的排序碰运气。
        panel.level = Self.ringLevel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: OrbitRingView(model: model))
        return panel
    }

    private static let scrimLevel = NSWindow.Level.floating
    private static let ringLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    /// 环和暗场共用一个外观 —— 它们是同一层，不能一个亮一个暗。
    ///
    /// Read once per summon rather than stored: the setting can change in the
    /// Settings window while no ring exists, and the next summon builds fresh
    /// panels anyway.
    private static var ringAppearance: NSAppearance? {
        OrbitPreferences.cardFinish.appearanceName.flatMap(NSAppearance.init(named:))
    }

    /// 铺满整块屏幕的暗场窗口。
    ///
    /// 单独一个窗口，而不是把环的面板撑满屏幕：the ring panel is sized and placed
    /// from the fan's own geometry, and every layout number in the view model
    /// reads off that size. Stretching it to the display would have made the
    /// dim free but turned the whole layout into a positioning problem inside a
    /// screen-sized canvas.
    ///
    /// It covers `frame`, not `visibleFrame`, so the menu bar recedes with
    /// everything else — a dim that stops short of the top edge reads as a
    /// window rather than as the desktop stepping back. It never takes events:
    /// the dim changes what the summon *looks* like, not what clicking anywhere
    /// on it does.
    private func makeScrim(
        for model: OrbitRingViewModel,
        ringFrame: NSRect,
        on screen: NSScreen?
    ) -> NSPanel? {
        guard let screen else { return nil }
        let bounds = screen.frame

        let panel = NSPanel(
            contentRect: bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = Self.ringAppearance
        panel.level = Self.scrimLevel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = NSHostingView(
            rootView: OrbitScrim(
                model: model,
                focus: scrimFocus(hub: model.hubCenterInPanel, ringFrame: ringFrame, screen: bounds),
                content: scrimContent(model.contentBounds, ringFrame: ringFrame, screen: bounds),
                // 「Backdrop color」原本只染卡片脚下那一小圈，几乎看不出改了什么。
                // 铺满屏幕的那团柔光才是这个偏好真正该管的东西 —— 现在调它，
                // 整个召唤层的气氛跟着变。
                bloom: model.showsBackdrop ? OrbitPalette.backdrop : nil
            )
        )
        panel.contentView = hosting
        return panel
    }

    /// 把星芯的位置从「面板内的 SwiftUI 坐标」翻成「整屏的单位坐标」。
    ///
    /// 两次翻转叠在一起，所以值得单独写出来：SwiftUI counts down from a view's
    /// top, AppKit counts up from the display's bottom, and the scrim's own
    /// SwiftUI space counts down again from the top of the screen.
    private func scrimFocus(hub: CGPoint, ringFrame: NSRect, screen: NSRect) -> UnitPoint {
        let screenX = ringFrame.minX + hub.x
        let topDownY = screen.maxY - (ringFrame.maxY - hub.y)
        return UnitPoint(
            x: (screenX - screen.minX) / max(screen.width, 1),
            y: topDownY / max(screen.height, 1)
        )
    }

    /// 同样的换算，只是这次搬的是一组相互独立的矩形。
    ///
    /// The rect's top edge in the panel becomes its top edge on screen, so the
    /// flip has to be applied to `maxY` and the height re-added — taking the
    /// corner alone would land the box a full height off. Keeping each rect
    /// separate prevents the scrim from filling the gap between the ring and
    /// preview with one oversized ellipse.
    private func scrimContent(_ rects: [CGRect], ringFrame: NSRect, screen: NSRect) -> [CGRect] {
        rects.map { rect in
            let originX = ringFrame.minX + rect.minX
            let topDownY = screen.maxY - (ringFrame.maxY - rect.minY)
            return CGRect(
                x: (originX - screen.minX) / max(screen.width, 1),
                y: topDownY / max(screen.height, 1),
                width: rect.width / max(screen.width, 1),
                height: rect.height / max(screen.height, 1)
            )
        }
    }

    /// The cursor only selects which screen the ring belongs to; whether the
    /// ring then follows the cursor or snaps to that screen's center is a
    /// user preference.
    private func anchor(for cursorLocation: CGPoint, on screen: NSScreen?) -> CGPoint {
        switch OrbitPreferences.ringPlacement {
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
