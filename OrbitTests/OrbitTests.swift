//
//  OrbitTests.swift
//  OrbitTests
//
//

import Testing
import AppKit
import UniformTypeIdentifiers
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

    /// 关掉最后一个窗口的应用会在 0 层留下一个够大的无标题窗口：Sequel Ace 是
    /// 500×500，Terminal 是 260×330。尺寸和层级都拦不住，只有标题能。
    ///
    /// This is the shape that puts a card on the ring whose preview then says
    /// "No windows to preview". The title test only runs when Screen Recording
    /// makes titles readable, so both answers have to hold.
    @Test func untitledPlaceholderWindowsAreDroppedOnlyWhenTitlesAreReadable() {
        func window(title: String? = nil) -> [String: Any] {
            var window: [String: Any] = [
                kCGWindowLayer as String: 0,
                kCGWindowBounds as String: [
                    "X": 0, "Y": 0, "Width": 500, "Height": 500,
                ] as [String: Any],
            ]
            if let title { window[kCGWindowName as String] = title }
            return window
        }

        // 读不到标题时只能放行，否则每个应用都会被当成没有窗口。
        #expect(WindowVisibilityChecker.isRealWindow(window()))

        #expect(!WindowVisibilityChecker.isRealWindow(window(), requiringTitle: true))
        #expect(!WindowVisibilityChecker.isRealWindow(window(title: ""), requiringTitle: true))
        #expect(WindowVisibilityChecker.isRealWindow(
            window(title: "Orbit — -zsh — 80×24"),
            requiringTitle: true
        ))
    }

    /// "问不出来"必须和"没有窗口"分开。
    ///
    /// The fallback in `AppListService` keys off `nil`, and nothing else. Keying
    /// it off an empty result is what let the title filter silently disable the
    /// whole setting: the filtered list came back empty and every windowless app
    /// was handed straight back.
    @Test func anUnanswerableWindowListIsNotAnEmptyOne() {
        // 窗口服务在这台机器上一定答得上来，哪怕答案里一个进程都没有。
        #expect(WindowVisibilityChecker.processesWithWindows() != nil)
    }

    /// 默认开启：`defaults.bool(forKey:)` 对没写过的键返回 false，正好是反的。
    @Test func windowlessAppsAreHiddenByDefault() {
        let previous = UserDefaults.standard.object(forKey: "hideWindowlessApps")
        UserDefaults.standard.removeObject(forKey: "hideWindowlessApps")
        defer { UserDefaults.standard.set(previous, forKey: "hideWindowlessApps") }

        #expect(OrbitConfig.hideWindowlessApps)
    }

    /// 下拉里列出的每一种语言，CFBundle 都必须真的能解析到 bundle 里的
    /// `.lproj`。写错一个标签（`zh-Hant` 打成 `zh-TW`）不会报任何错，用户选了
    /// 之后界面纹丝不动，而且无从查起。
    @Test func everyOfferedLanguageResolvesToABundledLocalization() {
        for code in AppLanguage.supported {
            let resolved = Bundle.preferredLocalizations(
                from: Bundle.main.localizations,
                forPreferences: [code]
            ).first
            #expect(resolved == code, "\(code) 没有解析到自己的 .lproj，实际拿到 \(resolved ?? "nil")")
        }
    }

    /// 「系统设置 › 语言与地区 › 应用程序」写进来的是带地区的完整标签。直接比对
    /// 一个都对不上，下拉会显示成"跟随系统"，而实际上并不是。
    @Test func regionTaggedLanguagesFromSystemSettingsAreRecognised() {
        #expect(AppLanguage.normalize("zh-Hant") == "zh-Hant")
        #expect(AppLanguage.normalize("zh-Hant-TW") == "zh-Hant")
        #expect(AppLanguage.normalize("en-CA") == "en")
        #expect(AppLanguage.normalize(nil) == nil)
        // 没做的语言不该被硬凑到某个做了的上面去。
        #expect(AppLanguage.normalize("sv") == nil)
    }

    /// 排序只看 id 和 name，其余字段给个能过编译的值就行。
    private func listed(_ id: String, _ name: String) -> AppInfo {
        AppInfo(
            id: id,
            name: name,
            icon: NSImage(size: NSSize(width: 1, height: 1)),
            bundleURL: nil,
            processIdentifier: 0
        )
    }

    /// 环上只放得下十二张卡，所以排序顺便决定了谁上得了环。按名字排再截断，
    /// 等于让首字母决定一个应用能不能被切换到。
    @Test func recentlyUsedAppsSortAheadOfEverythingElse() {
        let recent = ["com.c", "com.a"]
        let apps = [
            listed("com.z", "Zed"),
            listed("com.a", "Alpha"),
            listed("com.m", "Mid"),
            listed("com.c", "Charlie")
        ]

        let sorted = AppListService.byRecency(apps) { recent.firstIndex(of: $0) }

        // 有记录的按记录的先后，没记录的跟在后面按名字。
        #expect(sorted.map(\.id) == ["com.c", "com.a", "com.m", "com.z"])
    }

    /// 一条记录都没有时——Orbit 刚装好的第一次唤出——顺序必须退回按名字，
    /// 而不是退回成传进来的那个随机顺序。
    @Test func anEmptyHistoryLeavesTheListAlphabetical() {
        let apps = [
            listed("com.z", "Zed"),
            listed("com.a", "Alpha"),
            listed("com.m", "Mid")
        ]

        let sorted = AppListService.byRecency(apps) { _ in nil }

        #expect(sorted.map(\.name) == ["Alpha", "Mid", "Zed"])
    }

    /// 「按住、松开」要切回去的那个应用，跟卡片摆在哪没有关系 —— 按名字摆时，
    /// 第一张卡通常不是最近用过的那个。
    @Test func theMostRecentAppIsFoundRegardlessOfCardOrder() {
        let recent = ["com.c", "com.a"]
        let alphabetical = [
            listed("com.a", "Alpha"),
            listed("com.c", "Charlie"),
            listed("com.m", "Mid")
        ]

        let recentApp = AppListService.mostRecent(among: alphabetical) { recent.firstIndex(of: $0) }

        #expect(recentApp?.id == "com.c")
    }

    /// Orbit 自己的卡片是清理目标，不是一个可以切过去的应用；即使它排在最前面，
    /// 预选也绝不能落在它身上。
    @Test func orbitsOwnCardIsNeverThePreselection() {
        let apps = [AppInfo.orbit, listed("com.a", "Alpha")]

        let recentApp = AppListService.mostRecent(among: apps) { _ in 0 }

        #expect(recentApp?.isOrbit == false)
        #expect(recentApp?.id == "com.a")
    }

    /// 预选一个不在环上的应用，会让中心显示确认态、松手却什么也切不过去。
    @Test @MainActor func preselectingAnAppThatIsNotOnTheRingSelectsNothing() {
        let model = OrbitRingViewModel(
            apps: [listed("com.a", "Alpha")],
            showsPreview: false,
            preselecting: "com.not.here"
        )

        #expect(model.selectedID == nil)
        #expect(model.centerMode == .cancel)
    }

    @Test @MainActor func orbitCardCanBeShownOrHiddenFromTheRing() {
        let previous = UserDefaults.standard.object(forKey: "showOrbitCard")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "showOrbitCard")
            } else {
                UserDefaults.standard.removeObject(forKey: "showOrbitCard")
            }
        }

        OrbitConfig.showOrbitCard = true
        let shown = OrbitRingViewModel(apps: [.orbit], showsPreview: false)
        #expect(shown.apps.contains(where: { $0.isOrbit }))

        OrbitConfig.showOrbitCard = false
        let hidden = OrbitRingViewModel(apps: [.orbit], showsPreview: false)
        #expect(!hidden.apps.contains(where: { $0.isOrbit }))
    }

    @Test @MainActor func orbitCleanupKeepsRingOpenUntilTriggerRelease() {
        let model = OrbitRingViewModel(apps: [.orbit], showsPreview: false)
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.beginAppDrag(.orbit)
        model.updateAppDrag(.orbit, offset: .zero, overCenter: true)
        model.finishAppDrag(.orbit)

        #expect(!didCancel)

        model.triggerReleased()
        #expect(didCancel)
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

    @Test @MainActor func triggerReleaseAfterFileDropExitDismissesAfterReset() async throws {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.setFileDragTargeted(true)
        model.triggerReleased()
        #expect(!didCancel)

        model.setFileDragTargeted(false)
        try await Task.sleep(for: .seconds(OrbitConfig.fileDragExitGrace + 0.2))
        #expect(didCancel)
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

    /// 文件已经松手、URL 还在读的时候按 Escape，环不能说走就走。
    ///
    /// Dismissing releases the view model, and the completion handler that
    /// finishes the drop holds it weakly — so a cancel landing inside that
    /// window used to make an accepted AirDrop or Trash move disappear without
    /// a trace. The cancel is recorded and applied once the drop settles.
    @Test @MainActor func cancellingMidDropWaitsForTheDropToSettle() async throws {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        _ = model.handleFileDrop([])
        #expect(model.fileDropPhase == .completing)

        model.cancel()
        #expect(!didCancel)

        try await Task.sleep(for: .milliseconds(200))
        #expect(model.fileDropPhase == .idle)
        #expect(didCancel)
    }

    /// 同一个窗口里点中心也不能切走 —— 切换会关闭环，代价和取消一样。
    @Test @MainActor func theHubDoesNotSwitchAppsWhileADropIsCompleting() async throws {
        let model = OrbitRingViewModel(apps: [listed("com.a", "Alpha")])
        var activated: AppInfo?
        model.onActivate = { app, _ in activated = app }
        model.select(model.apps[0])

        _ = model.handleFileDrop([])
        model.confirmFromHub()
        #expect(activated == nil)

        try await Task.sleep(for: .milliseconds(200))
        model.confirmFromHub()
        #expect(activated?.id == "com.a")
    }

    /// 扔不进废纸篓的文件必须说出来。
    ///
    /// `trashItem` used to be called with `try?`, so a locked file, a volume
    /// with no Trash, or a path that no longer exists ended exactly like a
    /// success: the ring closed and the file stayed put.
    @Test @MainActor func aFailedTrashIsReportedOnTheHub() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orbit-not-a-real-file-\(UUID().uuidString)")
        let provider = NSItemProvider(
            item: missing.dataRepresentation as NSData,
            typeIdentifier: UTType.fileURL.identifier
        )

        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.fileTrashReady = true
        _ = model.handleFileDrop([provider])
        try await Task.sleep(for: .milliseconds(300))

        #expect(model.fileDropFailed)
        #expect(model.centerMode == .failed)
        #expect(!didCancel)
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

    /// 中心区域的每个状态都必须各画各的，而且画得出来。
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
