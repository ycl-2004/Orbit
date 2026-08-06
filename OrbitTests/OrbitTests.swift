//
//  OrbitTests.swift
//  OrbitTests
//
//

import Testing
import AppKit
@testable import Orbit

struct OrbitTests {

    @MainActor
    private func withShortcutSettings<T>(
        letters: Bool = false,
        numbers: Bool = false,
        _ body: () -> T
    ) -> T {
        let previousLetters = OrbitConfig.letterShortcutsEnabled
        let previousNumbers = OrbitConfig.numericShortcutsEnabled
        OrbitConfig.letterShortcutsEnabled = letters
        OrbitConfig.numericShortcutsEnabled = numbers
        defer {
            OrbitConfig.letterShortcutsEnabled = previousLetters
            OrbitConfig.numericShortcutsEnabled = previousNumbers
        }
        return body()
    }

    @Test func modifierRejectsMixedModifierFlags() {
        let option = TriggerModifier.option
        #expect(option.isPressed(in: [.maskAlternate]))
        #expect(option.otherModifiersPressed(in: [.maskAlternate, .maskShift]))
        #expect(!option.otherModifiersPressed(in: [.maskAlternate]))
    }

    /// `.disabled` 的掩码是空集，而 `OptionSet.contains([])` 恒为 `true`。
    /// 一旦这层保护被拿掉，"关闭取消选择键"会退化成"永远按着"。
    @Test func disabledModifierNeverCountsAsPressed() {
        let disabled = TriggerModifier.disabled
        #expect(!disabled.isPressed(in: []))
        #expect(!disabled.isPressed(in: [.maskCommand, .maskShift]))
        #expect(!disabled.otherModifiersPressed(in: [.maskCommand, .maskShift]))
    }

    /// 非修饰键的事件位（例如数字键盘标志）不该让触发手势失效。
    @Test func unrelatedEventFlagsDoNotCountAsCompetingModifiers() {
        let control = TriggerModifier.control
        #expect(control.isPressed(in: [.maskControl, .maskNumericPad]))
        #expect(!control.otherModifiersPressed(in: [.maskControl, .maskNumericPad]))
        #expect(control.otherModifiersPressed(in: [.maskControl, .maskCommand]))
    }

    @Test func onlyRealModifiersAreAssignable() {
        #expect(!TriggerModifier.assignable.contains(.disabled))
        #expect(TriggerModifier.assignable.count == TriggerModifier.allCases.count - 1)
    }

    /// 中心区域只在悬停阶段接收拖放；松手之后不该再响应。
    @Test func onlyHoveringPhasesReceiveTheDrop() {
        #expect(!FileDropPhase.idle.isReceiving)
        #expect(FileDropPhase.hovering.isReceiving)
        #expect(FileDropPhase.trashArmed.isReceiving)
        #expect(!FileDropPhase.completing.isReceiving)
    }

    /// 窗口表里绝大多数条目都不是「用户心里的那种窗口」。
    ///
    /// This predicate decides whether an app reaches the ring at all, so each
    /// rejected shape here is an app that would otherwise show up as a card
    /// with nothing behind it.
    @Test func onlyRealWindowsCountTowardsAnAppHavingWindows() {
        func window(
            layer: Int = 0,
            alpha: Double = 1,
            width: CGFloat = 400,
            height: CGFloat = 300
        ) -> [String: Any] {
            [
                kCGWindowLayer as String: layer,
                kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: [
                    "X": 0, "Y": 0, "Width": width, "Height": height,
                ] as [String: Any],
            ]
        }

        #expect(WindowVisibilityChecker.isRealWindow(window()))
        // 菜单栏、Dock、悬浮面板都在非 0 层。
        #expect(!WindowVisibilityChecker.isRealWindow(window(layer: 25)))
        // 完全透明的窗口在屏幕上等于不存在。
        #expect(!WindowVisibilityChecker.isRealWindow(window(alpha: 0)))
        // 自动填充气泡这类小面板不足以让一个应用值得切过去。
        #expect(!WindowVisibilityChecker.isRealWindow(window(width: 120, height: 80)))
        #expect(!WindowVisibilityChecker.isRealWindow([:]))
    }

    /// 尺寸门槛必须和预览侧共用一个来源，否则会出现「环上有卡片、预览说没窗口」。
    @Test func windowSizeThresholdIsSharedWithThePreview() {
        let size = OrbitConfig.minimumRealWindowSize
        #expect(WindowVisibilityChecker.isRealWindow([
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: [
                "X": 0, "Y": 0, "Width": size.width, "Height": size.height,
            ] as [String: Any],
        ]))
    }

    /// 默认开启：`defaults.bool(forKey:)` 对没写过的键返回 false，正好是反的。
    @Test func windowlessAppsAreHiddenByDefault() {
        let previous = UserDefaults.standard.object(forKey: "hideWindowlessApps")
        UserDefaults.standard.removeObject(forKey: "hideWindowlessApps")
        defer { UserDefaults.standard.set(previous, forKey: "hideWindowlessApps") }

        #expect(OrbitConfig.hideWindowlessApps)
    }

    @Test func firstLetterFoldsAccentsAndNonLatinNames() {
        func app(named name: String) -> AppInfo {
            AppInfo(
                id: name,
                name: name,
                icon: NSImage(size: NSSize(width: 1, height: 1)),
                bundleURL: nil,
                processIdentifier: getpid()
            )
        }

        #expect(app(named: "Safari").firstLetter == "S")
        #expect(app(named: "  Éditeur").firstLetter == "E")
        #expect(app(named: "微信").firstLetter == "W")
        #expect(app(named: "123").firstLetter == nil)
        #expect(app(named: "   ").firstLetter == nil)
    }

    @Test @MainActor func releasingWithoutSelectionCancels() {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.triggerReleased()

        #expect(didCancel)
    }

    @Test @MainActor func triggerReleaseDoesNotDismissDuringFileDrop() {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.setFileDragTargeted(true)
        model.triggerReleased()

        #expect(model.centerMode == .share)
        #expect(!didCancel)

        // Do not leave the hold timer running after the test.
        model.setFileDragTargeted(false)
    }

    /// 悬停到黑洞出现、再把文件拖走而不放手，环必须还能关掉。
    ///
    /// The exit path used to bail out whenever the trash was armed, so
    /// `fileDropPhase` stayed on `.trashArmed` forever. Both `cancel()` and
    /// `triggerReleased()` require `.idle`, which left the ring floating over
    /// everything with Escape, the trigger key and the hub all inert.
    @Test @MainActor func draggingFilesAwayAfterTheTrashArmsStillLetsTheRingClose() async throws {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.setFileDragTargeted(true)
        try await Task.sleep(for: .seconds(OrbitConfig.fileTrashHoldDuration + 0.2))
        #expect(model.centerMode == .trash)

        // 文件离开了窗口，但用户并没有放手 —— 不会有 drop 回调来收拾状态。
        model.setFileDragTargeted(false)
        try await Task.sleep(for: .seconds(OrbitConfig.fileDragExitGrace + 0.2))
        #expect(model.fileDropPhase == .idle)
        #expect(model.centerMode == .cancel)

        model.triggerReleased()
        #expect(didCancel)
    }

    /// 触发键设成 `.disabled` 会让环再也唤不出来，所以它连存都不该存得住。
    @Test func triggerModifierNeverResolvesToDisabled() {
        let previous = UserDefaults.standard.object(forKey: "triggerModifier")
        defer { UserDefaults.standard.set(previous, forKey: "triggerModifier") }

        UserDefaults.standard.set(TriggerModifier.disabled.rawValue, forKey: "triggerModifier")

        #expect(OrbitConfig.triggerModifier != .disabled)
        #expect(!TriggerModifier.assignable.contains(.disabled))

        OrbitConfig.triggerModifier = .disabled
        #expect(
            UserDefaults.standard.string(forKey: "triggerModifier") == TriggerModifier.option.rawValue
        )
    }

    /// 中心区域的五个状态必须各画各的，而且画得出来。
    ///
    /// A symbol name SwiftUI cannot resolve fails silently — the hub just renders
    /// empty — and two modes sharing one glyph is how "quit this app" and "throw
    /// these files away" came to look identical.
    @Test func everyCenterModeHasItsOwnResolvableIcon() {
        var seen: Set<String> = []
        for mode in OrbitCenterMode.allCases {
            let name = mode.iconName
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(mode) 用了一个不存在的 SF Symbol: \(name)"
            )
            #expect(seen.insert(name).inserted, "\(mode) 和别的模式共用了图标 \(name)")
        }
    }

    @Test @MainActor func selectionDoesNotActivateUntilConfirmed() {
        let app = AppInfo(
            id: "test.orbit.app",
            name: "Test App",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            bundleURL: nil,
            processIdentifier: getpid()
        )
        let model = OrbitRingViewModel(apps: [app])
        var didActivate = false
        model.onActivate = { _, _ in didActivate = true }

        model.select(app)
        #expect(!didActivate)

        model.triggerReleased()
        #expect(didActivate)
    }

    @Test @MainActor func keyboardNavigationSelectsWithoutActivating() {
        let first = AppInfo(
            id: "test.orbit.first",
            name: "First App",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            bundleURL: nil,
            processIdentifier: getpid()
        )
        let second = AppInfo(
            id: "test.orbit.second",
            name: "Second App",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            bundleURL: nil,
            processIdentifier: getpid()
        )
        let model = OrbitRingViewModel(apps: [first, second])
        var didActivate = false
        model.onActivate = { _, _ in didActivate = true }

        model.handle(.next, value: nil)
        #expect(model.selectedID == first.id)
        #expect(!didActivate)

        model.handle(.next, value: nil)
        #expect(model.selectedID == second.id)
        #expect(!didActivate)

        model.handle(.activate, value: nil)
        #expect(didActivate)
    }

    @Test @MainActor func deselectingLetsTheTriggerDismissWithoutActivating() {
        let app = AppInfo(
            id: "test.orbit.app",
            name: "Test App",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            bundleURL: nil,
            processIdentifier: getpid()
        )
        let model = OrbitRingViewModel(apps: [app])
        var didActivate = false
        var didCancel = false
        model.onActivate = { _, _ in didActivate = true }
        model.onCancel = { didCancel = true }

        model.select(app)
        #expect(model.selectedID == app.id)

        model.handle(.deselect, value: nil)
        #expect(model.selectedID == nil)

        model.triggerReleased()
        #expect(!didActivate)
        #expect(didCancel)
    }

    @Test @MainActor func arrowingAfterDeselectResumesWhereItLeftOff() {
        withShortcutSettings(numbers: true) {
            let apps = ["Safari", "Xcode", "Terminal", "Notes"].enumerated().map { index, name in
                AppInfo(
                    id: "test.orbit.\(index)",
                    name: name,
                    icon: NSImage(size: NSSize(width: 32, height: 32)),
                    bundleURL: nil,
                    processIdentifier: getpid()
                )
            }
            let model = OrbitRingViewModel(apps: apps)

            model.handle(.number, value: "3")
            #expect(model.selectedID == apps[2].id)

            model.handle(.deselect, value: nil)
            #expect(model.selectedID == nil)

            // Back to the third card, not the first.
            model.handle(.next, value: nil)
            #expect(model.selectedID == apps[2].id)

            // And from there it keeps moving normally.
            model.handle(.next, value: nil)
            #expect(model.selectedID == apps[3].id)
        }
    }

    @Test @MainActor func deselectTwiceStillResumesFromTheLatestPosition() {
        withShortcutSettings(numbers: true) {
            let apps = ["Safari", "Xcode", "Terminal"].enumerated().map { index, name in
                AppInfo(
                    id: "test.orbit.\(index)",
                    name: name,
                    icon: NSImage(size: NSSize(width: 32, height: 32)),
                    bundleURL: nil,
                    processIdentifier: getpid()
                )
            }
            let model = OrbitRingViewModel(apps: apps)

            model.handle(.number, value: "2")
            model.handle(.deselect, value: nil)
            model.handle(.next, value: nil)
            #expect(model.selectedID == apps[1].id)

            model.handle(.next, value: nil)
            model.handle(.deselect, value: nil)
            model.handle(.previous, value: nil)
            #expect(model.selectedID == apps[2].id)
        }
    }

    @Test @MainActor func numberAndLetterCommandsSelectExpectedCards() {
        withShortcutSettings(letters: true, numbers: true) {
            let apps = ["Safari", "Xcode", "Terminal"].enumerated().map { index, name in
                AppInfo(
                    id: "test.orbit.\(index)",
                    name: name,
                    icon: NSImage(size: NSSize(width: 32, height: 32)),
                    bundleURL: nil,
                    processIdentifier: getpid()
                )
            }
            let model = OrbitRingViewModel(apps: apps)

            model.handle(.number, value: "2")
            #expect(model.selectedID == apps[1].id)

            model.handle(.letter, value: "t")
            #expect(model.selectedID == apps[2].id)
        }
    }

    @Test @MainActor func optionalShortcutsStayDisabledByDefault() {
        withShortcutSettings {
            let apps = ["Safari", "Xcode"].enumerated().map { index, name in
                AppInfo(
                    id: "test.orbit.\(index)",
                    name: name,
                    icon: NSImage(size: NSSize(width: 32, height: 32)),
                    bundleURL: nil,
                    processIdentifier: getpid()
                )
            }
            let model = OrbitRingViewModel(apps: apps)

            model.handle(.number, value: "2")
            model.handle(.letter, value: "x")

            #expect(model.selectedID == nil)
        }
    }

}
