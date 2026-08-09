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
        let previousLetters = OrbitPreferences.letterShortcutsEnabled
        let previousNumbers = OrbitPreferences.numericShortcutsEnabled
        OrbitPreferences.letterShortcutsEnabled = letters
        OrbitPreferences.numericShortcutsEnabled = numbers
        defer {
            OrbitPreferences.letterShortcutsEnabled = previousLetters
            OrbitPreferences.numericShortcutsEnabled = previousNumbers
        }
        return body()
    }

    @Test func shortcutKeyRejectsMixedModifierFlags() {
        let alternate = ShortcutKey.alternate
        #expect(alternate.isDown(in: [.maskAlternate]))
        #expect(alternate.conflictsWithAnotherModifier(in: [.maskAlternate, .maskShift]))
        #expect(!alternate.conflictsWithAnotherModifier(in: [.maskAlternate]))
    }

    /// `.disabled` 的掩码是空集，而 `OptionSet.contains([])` 恒为 `true`。
    /// 一旦这层保护被拿掉，"关闭取消选择键"会退化成"永远按着"。
    @Test func optionalShortcutNeverCountsAsPressed() {
        let absent = ShortcutKey.none
        #expect(!absent.isDown(in: []))
        #expect(!absent.isDown(in: [.maskCommand, .maskShift]))
        #expect(!absent.conflictsWithAnotherModifier(in: [.maskCommand, .maskShift]))
    }

    /// 非修饰键的事件位（例如数字键盘标志）不该让触发手势失效。
    @Test func unrelatedEventFlagsDoNotCountAsCompetingModifiers() {
        let control = ShortcutKey.control
        #expect(control.isDown(in: [.maskControl, .maskNumericPad]))
        #expect(!control.conflictsWithAnotherModifier(in: [.maskControl, .maskNumericPad]))
        #expect(control.conflictsWithAnotherModifier(in: [.maskControl, .maskCommand]))
    }

    @Test func onlyRealModifiersAreAssignable() {
        #expect(!ShortcutKey.usableForSummon.contains(.none))
        #expect(ShortcutKey.usableForSummon.count == ShortcutKey.allCases.count - 1)
    }

    /// 中心区域只在悬停阶段接收拖放；松手之后不该再响应。
    @Test func onlyHoveringPhasesReceiveTheDrop() {
        #expect(!DropLifecycle.resting.acceptsHover)
        #expect(DropLifecycle.sharing.acceptsHover)
        #expect(DropLifecycle.trashReady.acceptsHover)
        #expect(!DropLifecycle.processing.acceptsHover)
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

        #expect(WindowServerInspector.qualifiesAsWindow(window()))
        // 菜单栏、Dock、悬浮面板都在非 0 层。
        #expect(!WindowServerInspector.qualifiesAsWindow(window(layer: 25)))
        // 完全透明的窗口在屏幕上等于不存在。
        #expect(!WindowServerInspector.qualifiesAsWindow(window(alpha: 0)))
        // 自动填充气泡这类小面板不足以让一个应用值得切过去。
        #expect(!WindowServerInspector.qualifiesAsWindow(window(width: 120, height: 80)))
        #expect(!WindowServerInspector.qualifiesAsWindow([:]))
    }

    /// 尺寸门槛必须和预览侧共用一个来源，否则会出现「环上有卡片、预览说没窗口」。
    @Test func windowSizeThresholdIsSharedWithThePreview() {
        let size = OrbitPreferences.minimumRealWindowSize
        #expect(WindowServerInspector.qualifiesAsWindow([
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
        #expect(WindowServerInspector.qualifiesAsWindow(window()))

        #expect(!WindowServerInspector.qualifiesAsWindow(window(), requiringTitle: true))
        #expect(!WindowServerInspector.qualifiesAsWindow(window(title: ""), requiringTitle: true))
        #expect(WindowServerInspector.qualifiesAsWindow(
            window(title: "Orbit — -zsh — 80×24"),
            requiringTitle: true
        ))
    }

    /// "问不出来"必须和"没有窗口"分开。
    ///
    /// The fallback in the application catalog keys off `nil`, and nothing else. Keying
    /// it off an empty result is what let the title filter silently disable the
    /// whole setting: the filtered list came back empty and every windowless app
    /// was handed straight back.
    @Test func anUnanswerableWindowListIsNotAnEmptyOne() {
        // 窗口服务在这台机器上一定答得上来，哪怕答案里一个进程都没有。
        #expect(WindowServerInspector.windowOwners() != nil)
    }

    /// 默认开启：`defaults.bool(forKey:)` 对没写过的键返回 false，正好是反的。
    @Test func windowlessAppsAreHiddenByDefault() {
        let previous = UserDefaults.standard.object(forKey: "hideWindowlessApps")
        UserDefaults.standard.removeObject(forKey: "hideWindowlessApps")
        defer { UserDefaults.standard.set(previous, forKey: "hideWindowlessApps") }

        #expect(OrbitPreferences.hideWindowlessApps)
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
    private func listed(_ id: String, _ name: String, processIdentifier: pid_t = 0) -> AppRecord {
        AppRecord(
            id: id,
            name: name,
            icon: NSImage(size: NSSize(width: 1, height: 1)),
            bundleURL: nil,
            processIdentifier: processIdentifier
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

        let sorted = RunningAppCatalog.orderedByUse(apps) { recent.firstIndex(of: $0) }

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

        let sorted = RunningAppCatalog.orderedByUse(apps) { _ in nil }

        #expect(sorted.map(\.name) == ["Alpha", "Mid", "Zed"])
    }

    @Test func alphabeticalArrangementKeepsThePreviousAppAsItsAnchor() {
        let recentlyUsed = [
            listed("com.previous", "Zulu"),
            listed("com.older-b", "Beta"),
            listed("com.older-a", "Alpha")
        ]

        let arranged = RunningAppCatalog.arranged(recentlyUsed, by: .alphabetical)

        #expect(arranged.map(\.id) == ["com.previous", "com.older-a", "com.older-b"])
    }

    @Test @MainActor func openingBehaviorDefaultsToCancelAndKeepsQuickSwitchSelectable() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "ringOpeningBehavior")
        defer {
            if let previous {
                defaults.set(previous, forKey: "ringOpeningBehavior")
            } else {
                defaults.removeObject(forKey: "ringOpeningBehavior")
            }
        }

        defaults.removeObject(forKey: "ringOpeningBehavior")
        #expect(OrbitPreferences.ringOpeningBehavior == .cancel)

        OrbitPreferences.ringOpeningBehavior = .quickSwitch
        #expect(OrbitPreferences.ringOpeningBehavior == .quickSwitch)
    }

    /// If the current app has another actionable window, that window is the
    /// newest switch destination. It therefore owns the same first slot in
    /// both visual arrangement modes; cleanup never participates here.
    @Test func theCurrentAppsOtherWindowOwnsTheTwelveOClockTarget() {
        let current = listed("com.current", "Zulu", processIdentifier: 42)
        let ranked = [
            listed("com.previous", "Previous", processIdentifier: 99),
            listed("com.older", "Alpha", processIdentifier: 100)
        ]

        let recent = RunningAppCatalog.switchTargets(
            rankedApps: ranked,
            currentApp: current,
            limit: 3,
            order: .recent
        )
        let alphabetical = RunningAppCatalog.switchTargets(
            rankedApps: ranked,
            currentApp: current,
            limit: 3,
            order: .alphabetical
        )

        #expect(recent.map(\.id) == ["com.current", "com.previous", "com.older"])
        #expect(alphabetical.map(\.id) == ["com.current", "com.older", "com.previous"])
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

    @Test @MainActor func previousAppAlwaysOccupiesTheTwelveOClockAnchor() {
        let apps = [listed("com.previous", "Previous"), listed("com.older", "Older")]
        let withoutPreview = OrbitRingViewModel(apps: apps, showsPreview: false)
        let withPreview = OrbitRingViewModel(apps: apps, showsPreview: true)

        #expect(abs(withoutPreview.angle(for: 0) + .pi / 2) < 0.000_001)
        #expect(abs(withPreview.angle(for: 0) + .pi / 2) < 0.000_001)
        #expect(withoutPreview.angle(for: 1) < withoutPreview.angle(for: 0))
        #expect(withPreview.angle(for: 1) < withPreview.angle(for: 0))
    }

    @Test @MainActor func eitherArrowEntersANeutralRingAtThePreviousApp() {
        let apps = [
            listed("com.previous", "Previous"),
            listed("com.older", "Older"),
            AppRecord.orbitCard
        ]
        let movingForward = OrbitRingViewModel(apps: apps, showsPreview: false)
        let movingBackward = OrbitRingViewModel(apps: apps, showsPreview: false)

        movingForward.moveSelection(step: 1)
        movingBackward.moveSelection(step: -1)

        #expect(movingForward.selectedID == "com.previous")
        #expect(movingBackward.selectedID == "com.previous")
    }

    /// Orbit 自己那张卡是清理入口，不是切换目标 —— 确认它只会关掉圆环。所以
    /// 方向键进入一个空选的环时要跳过它，而这正是快速切换预选时用的同一条规则：
    /// 两边不一致的话，同样是松开触发键，结果会取决于高亮是谁放上去的。
    @Test @MainActor func neutralEntrySkipsTheOrbitCardTheWayQuickSwitchDoes() {
        let withRealTarget = OrbitRingViewModel(
            apps: [AppRecord.orbitCard, listed("com.previous", "Previous")],
            showsPreview: false
        )
        #expect(withRealTarget.entryCardID == "com.previous")
        withRealTarget.moveSelection(step: 1)
        #expect(withRealTarget.selectedID == "com.previous")

        // 环上只剩 Orbit 一张卡时没有别的可落，仍然要有个确定的答案。
        let orbitOnly = OrbitRingViewModel(apps: [AppRecord.orbitCard], showsPreview: false)
        #expect(orbitOnly.entryCardID == AppRecord.orbitCard.id)
    }

    @Test @MainActor func currentAppWindowTargetCanConfirmBeforePreviewCaptureFinishes() {
        let current = listed("com.current", "Current", processIdentifier: 42)
        let target = WindowTarget(
            id: 200,
            title: "Previous Chrome window",
            frame: CGRect(x: 20, y: 20, width: 1200, height: 800)
        )
        let model = OrbitRingViewModel(
            apps: [current],
            showsPreview: false,
            currentWindow: CurrentWindow(processIdentifier: 42, id: 100),
            recentCurrentAppWindowIDs: [100, 200],
            preferredCurrentAppWindow: target
        )
        var activatedWindow: WindowTarget?
        model.onActivate = { _, window in activatedWindow = window }

        #expect(model.selectedID == nil)
        #expect(model.centerMode == .cancel)
        model.moveSelection(step: 1)
        model.triggerReleased()

        #expect(activatedWindow == target)
    }

    /// 松手往往赶在缩略图截完之前，而「切到哪扇窗」根本不需要缩略图 —— 窗口号、
    /// 标题和位置窗口服务同步就能给。以前只有「你此刻就在的那个应用」备了这条同步
    /// 答案，别的应用一律答 nil，于是切到 Chrome 时退化成普通的应用激活：应用到了
    /// 前面，却停在它自己记得的那扇窗上，而不是你选的那扇。
    @Test func anotherAppsWindowTargetIsKnownBeforeAnyThumbnailExists() {
        let chromeWindow = WindowTarget(
            id: 300,
            title: "The window you picked",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )
        var asked: (pid_t, CGWindowID?, [CGWindowID])?

        let target = OrbitRingViewModel.windowTargetWithoutCapture(
            for: listed("com.browser", "Chrome", processIdentifier: 77),
            currentWindow: CurrentWindow(processIdentifier: 42, id: 100),
            preferredCurrentAppWindow: WindowTarget(id: 200, title: "Other app", frame: .zero),
            recentWindowIDs: [300, 400],
            lookup: { pid, excluded, preferred in
                asked = (pid, excluded, preferred)
                return chromeWindow
            }
        )

        #expect(target == chromeWindow)
        #expect(asked?.0 == 77)
        // 别的应用没有「你正看着的那一扇」要躲开：它的每一扇窗都是合法目的地。
        #expect(asked?.1 == nil)
        #expect(asked?.2 == [300, 400])
    }

    /// 而你此刻就在的那个应用继续用唤出瞬间算好的那条答案 —— 那时 Orbit 的面板还
    /// 没进窗口表，「你正看着哪一扇」才问得出来，现在再算已经晚了。
    @Test func theCurrentAppKeepsTheTargetComputedWhenTheRingOpened() {
        let precomputed = WindowTarget(id: 200, title: "Previous sibling", frame: .zero)
        var lookupRan = false

        let target = OrbitRingViewModel.windowTargetWithoutCapture(
            for: listed("com.current", "Current", processIdentifier: 42),
            currentWindow: CurrentWindow(processIdentifier: 42, id: 100),
            preferredCurrentAppWindow: precomputed,
            recentWindowIDs: [100, 200],
            lookup: { _, _, _ in
                lookupRan = true
                return WindowTarget(id: 999, title: "Recomputed", frame: .zero)
            }
        )

        #expect(target == precomputed)
        #expect(!lookupRan)
    }

    @Test @MainActor func dismissalExplicitlyRestoresTheCancelState() {
        let model = OrbitRingViewModel(
            apps: [listed("com.a", "Alpha")],
            showsPreview: false,
            preselecting: "com.a"
        )

        #expect(model.centerMode == .confirm)
        model.resetForDismissal()

        #expect(model.selectedID == nil)
        #expect(model.selectedWindowIndex == 0)
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

        OrbitPreferences.showOrbitCard = true
        let shown = OrbitRingViewModel(apps: [.orbitCard], showsPreview: false)
        #expect(shown.apps.contains(where: { $0.isOrbit }))

        OrbitPreferences.showOrbitCard = false
        let hidden = OrbitRingViewModel(apps: [.orbitCard], showsPreview: false)
        #expect(!hidden.apps.contains(where: { $0.isOrbit }))
    }

    @Test @MainActor func orbitCleanupKeepsRingOpenUntilTriggerRelease() {
        let model = OrbitRingViewModel(apps: [.orbitCard], showsPreview: false)
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.beginAppDrag(.orbitCard)
        model.updateAppDrag(.orbitCard, offset: .zero, overCenter: true)
        model.finishAppDrag(.orbitCard)

        #expect(!didCancel)

        model.triggerReleased()
        #expect(didCancel)
    }

    @Test func firstLetterFoldsAccentsAndNonLatinNames() {
        func app(named name: String) -> AppRecord {
            AppRecord(
                id: name,
                name: name,
                icon: NSImage(size: NSSize(width: 1, height: 1)),
                bundleURL: nil,
                processIdentifier: getpid()
            )
        }

        #expect(app(named: "Safari").letterShortcut == "S")
        #expect(app(named: "  Éditeur").letterShortcut == "E")
        #expect(app(named: "微信").letterShortcut == "W")
        #expect(app(named: "123").letterShortcut == nil)
        #expect(app(named: "   ").letterShortcut == nil)
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
        try await Task.sleep(for: .seconds(OrbitPreferences.fileDragExitGrace + 0.2))
        #expect(didCancel)
    }

    /// 悬停到黑洞出现、再把文件拖走而不放手，环必须还能关掉。
    ///
    /// The exit path used to bail out whenever the trash was armed, so
    /// `fileDropPhase` stayed on `.trashReady` forever. Both `cancel()` and
    /// `triggerReleased()` require `.resting`, which left the ring floating over
    /// everything with Escape, the trigger key and the hub all inert.
    @Test @MainActor func draggingFilesAwayAfterTheTrashArmsStillLetsTheRingClose() async throws {
        let model = OrbitRingViewModel(apps: [])
        var didCancel = false
        model.onCancel = { didCancel = true }

        model.setFileDragTargeted(true)
        try await Task.sleep(for: .seconds(OrbitPreferences.fileTrashHoldDuration + 0.2))
        #expect(model.centerMode == .trash)

        // 文件离开了窗口，但用户并没有放手 —— 不会有 drop 回调来收拾状态。
        model.setFileDragTargeted(false)
        try await Task.sleep(for: .seconds(OrbitPreferences.fileDragExitGrace + 0.2))
        #expect(model.fileDropPhase == .resting)
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
        #expect(model.fileDropPhase == .processing)

        model.cancel()
        #expect(!didCancel)

        try await Task.sleep(for: .milliseconds(200))
        #expect(model.fileDropPhase == .resting)
        #expect(didCancel)
    }

    /// 同一个窗口里点中心也不能切走 —— 切换会关闭环，代价和取消一样。
    @Test @MainActor func theHubDoesNotSwitchAppsWhileADropIsCompleting() async throws {
        let model = OrbitRingViewModel(apps: [listed("com.a", "Alpha")])
        var activated: AppRecord?
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

    /// 触发键设成 `.none` 会让环再也唤不出来，所以它连存都不该存得住。
    @Test @MainActor func summonKeyAlwaysHasAValue() {
        let previous = UserDefaults.standard.object(forKey: "summonKey")
        defer { UserDefaults.standard.set(previous, forKey: "summonKey") }

        UserDefaults.standard.set(ShortcutKey.none.rawValue, forKey: "summonKey")

        #expect(OrbitPreferences.summonKey != .none)
        #expect(!ShortcutKey.usableForSummon.contains(.none))

        OrbitPreferences.summonKey = .none
        #expect(
            UserDefaults.standard.string(forKey: "summonKey") == ShortcutKey.alternate.rawValue
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
        let app = AppRecord(
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
        let first = AppRecord(
            id: "test.orbit.first",
            name: "First App",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            bundleURL: nil,
            processIdentifier: getpid()
        )
        let second = AppRecord(
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
        let app = AppRecord(
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
                AppRecord(
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
                AppRecord(
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
                AppRecord(
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
                AppRecord(
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

    // MARK: - 窗口重定位（focus 的匹配逻辑）

    /// ScreenCaptureKit 和 Accessibility 对同一个窗口报的标题格式不同 ——
    /// Chrome 实测：SC 报 `PV UV 数据处理`，AX 报
    /// `PV UV 数据处理 - Google Chrome - YC (AI Profile)`。
    /// 匹配必须双向前缀，否则浏览器窗口永远对不上。
    @Test func windowTitlesAgreeAcrossFrameworkFormats() {
        // Chrome 真实标题对：AX 比 SC 长
        #expect(WindowPreviewService.titles(
            "PV UV 数据处理 - Google Chrome - YC (AI Profile)",
            agreeWith: "PV UV 数据处理"
        ))
        // 反方向：SC 比 AX 长（有些应用 AX 报短标题）
        #expect(WindowPreviewService.titles(
            "Notes",
            agreeWith: "Notes — All iCloud"
        ))
        // 严格相等自然算
        #expect(WindowPreviewService.titles("Terminal", agreeWith: "Terminal"))
        // 无前缀关系不算
        #expect(!WindowPreviewService.titles("Settings", agreeWith: "PV UV 数据处理"))
        // 中途不同只有共同前缀，也不算
        #expect(!WindowPreviewService.titles("Report v1", agreeWith: "Report v2"))
    }

    /// 空标题谁也不匹配：无标题窗口靠 frame 兜底，绝不能靠「空==空」误配。
    @Test func emptyWindowTitlesNeverAgree() {
        #expect(!WindowPreviewService.titles("", agreeWith: ""))
        #expect(!WindowPreviewService.titles("", agreeWith: "Safari"))
        #expect(!WindowPreviewService.titles("Safari", agreeWith: ""))
        #expect(!WindowPreviewService.titles(nil, agreeWith: "Safari"))
    }

    /// SC 和 AX 报同一个窗口的 frame 允许 2pt 舍入差；再大就是另一扇窗。
    @Test func windowFrameMatchingToleratesRounding() {
        let base = CGRect(x: 100, y: 200, width: 800, height: 600)
        #expect(base.matches(base))
        #expect(base.matches(CGRect(x: 102, y: 198, width: 798, height: 602)))
        #expect(!base.matches(CGRect(x: 103, y: 200, width: 800, height: 600)))
        #expect(!base.matches(CGRect(x: 100, y: 200, width: 800, height: 597)))
        // 位置相同、尺寸不同 = 不同窗口（同 app 常见同位置层叠）
        #expect(!base.matches(CGRect(x: 100, y: 200, width: 400, height: 300)))
    }

    /// 标题要嵌进 AppleScript 字符串字面量，引号和反斜杠必须转义 ——
    /// 网页标题里出现引号是常态，不转义就是脚本注入。
    @Test func appleScriptTitleEscaping() {
        #expect(ScriptedWindowFocus.escaped(#"He said "hi""#) == #"He said \"hi\""#)
        #expect(ScriptedWindowFocus.escaped(#"C:\path"#) == #"C:\\path"#)
        // 反斜杠先转义，再转义引号：\" → \\\"
        #expect(ScriptedWindowFocus.escaped(#"\""#) == #"\\\""#)
        #expect(ScriptedWindowFocus.escaped("普通标题") == "普通标题")
    }

    // MARK: - 你此刻就在的那个应用

    /// 当前应用的卡只有一个用途：切到它**别的**窗口。只有一扇窗时那张卡只会
    /// 把你送回原地，不给；有多扇时必须给，否则那些窗口一个都够不着。
    @Test func theAppYouAreInGetsACardOnlyWhenItHasOtherWindows() {
        #expect(RunningAppCatalog.currentAppDeservesCard(42, windowCounts: [42: 3]))
        #expect(RunningAppCatalog.currentAppDeservesCard(42, windowCounts: [42: 2]))
        // 只有一扇 = 就是你正看着的那扇
        #expect(!RunningAppCatalog.currentAppDeservesCard(42, windowCounts: [42: 1]))
        #expect(!RunningAppCatalog.currentAppDeservesCard(42, windowCounts: [42: 0]))
        #expect(!RunningAppCatalog.currentAppDeservesCard(42, windowCounts: [:]))
        // 窗口服务没作答时保持旧行为：不给卡
        #expect(!RunningAppCatalog.currentAppDeservesCard(42, windowCounts: nil))
        #expect(!RunningAppCatalog.currentAppDeservesCard(nil, windowCounts: [42: 3]))
    }

    @Test func windowHistoryMakesThePreviouslyViewedSiblingMostRecent() {
        var history = WindowActivationHistory(perAppLimit: 3)

        history.record(100, for: "com.browser")
        history.record(200, for: "com.browser")
        history.record(300, for: "com.browser")
        history.record(200, for: "com.browser")

        #expect(history.recentWindowIDs(for: "com.browser") == [200, 300, 100])
        #expect(history.recentWindowIDs(for: "com.other").isEmpty)
    }

    @Test func alternateWindowUsesWindowMRUAndNeverReturnsTheCurrentWindow() {
        func window(_ id: Int, _ title: String, isOnScreen: Bool = true) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: 42,
                kCGWindowNumber as String: id,
                kCGWindowName as String: title,
                kCGWindowLayer as String: 0,
                kCGWindowAlpha as String: 1.0,
                kCGWindowIsOnscreen as String: isOnScreen,
                kCGWindowBounds as String: [
                    "X": 0,
                    "Y": 0,
                    "Width": 1200,
                    "Height": 800
                ]
            ]
        }

        let target = WindowServerInspector.mostRecentOtherWindow(
            in: [window(100, "Current"), window(300, "Older"), window(200, "Previous")],
            ownedBy: 42,
            excluding: 100,
            preferredIDs: [100, 200, 300],
            requiringTitle: true
        )

        #expect(target?.id == 200)
        #expect(target?.title == "Previous")

        let unavailableWithoutTitles = WindowServerInspector.mostRecentOtherWindow(
            in: [window(100, "", isOnScreen: true), window(200, "", isOnScreen: false)],
            ownedBy: 42,
            excluding: 100,
            preferredIDs: [100, 200],
            requiringTitle: false
        )
        #expect(unavailableWithoutTitles == nil)

        // 换一个应用来问的时候没有「正看着的那一扇」要躲开，最近用过的那一扇就是
        // 答案 —— 包括它在别的应用里会被当作当前窗口排除掉的那一号。
        let inAnotherApp = WindowServerInspector.mostRecentOtherWindow(
            in: [window(100, "First"), window(200, "Second")],
            ownedBy: 42,
            excluding: nil,
            preferredIDs: [100],
            requiringTitle: true
        )
        #expect(inAnotherApp?.id == 100)
    }

    /// 每一级切换报的都只是「请求被接受了」：AX 的 raise 对一扇它根本没去成的窗
    /// 照样报成功，Chromium 的 `set index` 原地重排一下也报成功。回头问一次窗口
    /// 服务，是唯一能分辨「你到了」和「应用到了前面但停在别的窗上」的办法。
    @Test func aSwitchOnlyCountsAsLandedWhenTheTargetIsTheFrontWindow() {
        let size = OrbitPreferences.minimumRealWindowSize
        func window(id: Int, title: String?) -> [String: Any] {
            var value: [String: Any] = [
                kCGWindowOwnerPID as String: 42,
                kCGWindowNumber as String: id,
                kCGWindowLayer as String: 0,
                kCGWindowAlpha as String: 1.0,
                kCGWindowBounds as String: [
                    "X": 0,
                    "Y": 0,
                    "Width": size.width + 1,
                    "Height": size.height + 1
                ]
            ]
            if let title { value[kCGWindowName as String] = title }
            return value
        }

        // 切对了：目标就是最前的那扇。
        #expect(
            WindowServerInspector.switchLanded(
                in: [window(id: 200, title: "Picked"), window(id: 100, title: "Old")],
                on: 200,
                ownedBy: 42,
                requiringTitle: true
            )
        )
        // 应用到了前面，却停在它自己记得的那扇窗上 —— 正是要认出来的那个失败。
        #expect(
            !WindowServerInspector.switchLanded(
                in: [window(id: 100, title: "Old"), window(id: 200, title: "Picked")],
                on: 200,
                ownedBy: 42,
                requiringTitle: true
            )
        )
        // 目标在别的 Space 上，压根不在这份表里。
        #expect(
            !WindowServerInspector.switchLanded(
                in: [window(id: 100, title: "Old")],
                on: 200,
                ownedBy: 42,
                requiringTitle: true
            )
        )

        // 没有屏幕录制权限时标题一律读不到，而 Chromium 的全屏窗会把无标题的容器
        // 面排在页面前头。严判会把每一次正确的切换都判成失败，然后把整条降级链再
        // 跑一遍；退到「目标露面了没有」这个问得出来的问题。
        let untitled = [window(id: 804, title: nil), window(id: 735, title: nil)]
        #expect(
            WindowServerInspector.switchLanded(
                in: untitled,
                on: 735,
                ownedBy: 42,
                requiringTitle: false
            )
        )
        #expect(
            !WindowServerInspector.switchLanded(
                in: untitled,
                on: 999,
                ownedBy: 42,
                requiringTitle: false
            )
        )
    }

    /// 预览只藏「你正看着的那一扇」，而且只在你正用的那个应用里藏 ——
    /// 别的应用的同号窗口不受影响。
    @Test func onlyTheWindowYouAreLookingAtIsHiddenAndOnlyInItsOwnApp() {
        let current = CurrentWindow(processIdentifier: 42, id: 7)
        #expect(current.hiddenWindow(inAppWith: 42) == 7)
        #expect(current.hiddenWindow(inAppWith: 99) == nil)
    }

    /// Fullscreen Chrome puts untitled normal-layer toolbar/container surfaces
    /// ahead of the titled page in the on-screen window list. The page ID is
    /// what ScreenCaptureKit previews and therefore the one Orbit must hide.
    @Test func currentWindowSkipsChromesUntitledFullscreenSurfaces() {
        let size = OrbitPreferences.minimumRealWindowSize
        func window(id: Int, title: String?) -> [String: Any] {
            var value: [String: Any] = [
                kCGWindowOwnerPID as String: 42,
                kCGWindowNumber as String: id,
                kCGWindowLayer as String: 0,
                kCGWindowAlpha as String: 1.0,
                kCGWindowBounds as String: [
                    "X": 0,
                    "Y": 0,
                    "Width": size.width + 1,
                    "Height": size.height + 1
                ]
            ]
            if let title { value[kCGWindowName as String] = title }
            return value
        }

        let windows = [
            window(id: 804, title: nil),
            window(id: 735, title: "Current page")
        ]

        #expect(
            WindowServerInspector.frontWindow(
                in: windows,
                ownedBy: 42,
                requiringTitle: true
            ) == 735
        )
    }

    /// 没有屏幕录制权限时所有标题都读成 nil，此时还硬要一个标题，等于答不出
    /// 「你正看着哪一扇窗」——而那是「当前应用要不要给一张卡」的起点，整条
    /// 「切到同一应用的另一扇窗」会跟着一起消失。要求标题必须跟着权限走。
    @Test func theFrontWindowStaysResolvableWithoutScreenRecording() {
        let size = OrbitPreferences.minimumRealWindowSize
        func window(id: Int) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: 42,
                kCGWindowNumber as String: id,
                kCGWindowLayer as String: 0,
                kCGWindowAlpha as String: 1.0,
                kCGWindowBounds as String: [
                    "X": 0,
                    "Y": 0,
                    "Width": size.width + 1,
                    "Height": size.height + 1
                ]
            ]
        }

        // 权限不在时窗口表里一个标题都没有。
        let untitled = [window(id: 804), window(id: 735)]

        #expect(
            WindowServerInspector.frontWindow(
                in: untitled,
                ownedBy: 42,
                requiringTitle: false
            ) == 804
        )
        #expect(
            WindowServerInspector.frontWindow(
                in: untitled,
                ownedBy: 42,
                requiringTitle: true
            ) == nil
        )
    }

    /// 对一个应用首次发 Apple Event 会弹系统授权框，而脚本一直阻塞到那个框被
    /// 回答为止。等用户一分钟后才点「不允许」，他早就在做别的事了 —— 这时候再
    /// 兜底激活一个应用是打断，不是把这次切换做完。
    @Test func aLateAppleEventsAnswerNoLongerActivatesTheApp() {
        #expect(ScriptedWindowFocus.fallbackActivationIsStillRelevant(elapsed: 0))
        #expect(ScriptedWindowFocus.fallbackActivationIsStillRelevant(
            elapsed: OrbitPreferences.maximumSwitchFallbackDelay
        ))
        #expect(!ScriptedWindowFocus.fallbackActivationIsStillRelevant(
            elapsed: OrbitPreferences.maximumSwitchFallbackDelay + 0.01
        ))
        #expect(!ScriptedWindowFocus.fallbackActivationIsStillRelevant(elapsed: 60))
    }

    /// A Window-menu press already switches Spaces inside the current app.
    /// Reactivating that process afterwards can restore its old fullscreen
    /// window. Only a target app that was not frontmost needs activation.
    @Test func currentAppWindowMenuSwitchIsNotUndoneByReactivation() {
        #expect(!ScriptedWindowFocus.needsActivationAfterWindowMenu(
            targetProcess: 42,
            originatingFrontmostProcess: 42
        ))
        #expect(ScriptedWindowFocus.needsActivationAfterWindowMenu(
            targetProcess: 42,
            originatingFrontmostProcess: 99
        ))
        #expect(ScriptedWindowFocus.needsActivationAfterWindowMenu(
            targetProcess: 42,
            originatingFrontmostProcess: nil
        ))
    }

    /// `cannotComplete` means the target app did not answer before the AX
    /// timeout; Apple explicitly warns that the requested action may still
    /// have happened. Treating it as failure would run the fallback and undo
    /// a fullscreen Space switch that is already underway.
    @Test func anAXTimeoutDoesNotCancelAPossiblyAcceptedWindowMenuAction() {
        #expect(ScriptedWindowFocus.actionWasAccepted(.success))
        #expect(ScriptedWindowFocus.actionWasAccepted(.cannotComplete))
        #expect(!ScriptedWindowFocus.actionWasAccepted(.actionUnsupported))
        #expect(!ScriptedWindowFocus.actionWasAccepted(.invalidUIElement))
    }

    /// Chrome can expose an AX window and return success for `AXRaise` even
    /// though that fullscreen window remains on another Space. Same-process,
    /// off-screen targets must continue to the Window-menu fallback; ordinary
    /// same-Space raises and cross-application activation remain valid.
    @Test func aSuccessfulAXRaiseCannotFinishASameAppCrossSpaceSwitch() {
        #expect(!WindowPreviewService.directFocusCanCompleteSwitch(
            focusSucceeded: true,
            targetWasOnScreen: false,
            targetProcess: 42,
            originatingFrontmostProcess: 42
        ))
        #expect(WindowPreviewService.directFocusCanCompleteSwitch(
            focusSucceeded: true,
            targetWasOnScreen: true,
            targetProcess: 42,
            originatingFrontmostProcess: 42
        ))
        #expect(WindowPreviewService.directFocusCanCompleteSwitch(
            focusSucceeded: true,
            targetWasOnScreen: false,
            targetProcess: 42,
            originatingFrontmostProcess: 99
        ))
        #expect(!WindowPreviewService.directFocusCanCompleteSwitch(
            focusSucceeded: false,
            targetWasOnScreen: true,
            targetProcess: 42,
            originatingFrontmostProcess: 99
        ))
    }

    /// Window 菜单靠内容认，不靠菜单标题 —— 标题跟着应用自己的界面语言走。
    /// History/Bookmarks 可能回显*一个*窗口标题（当前页面），只有 Window 菜单
    /// 全都列；两个不同命中是判据。
    @Test func windowMenuIsRecognisedByItsContentsNotItsTitle() {
        let windows = ["Browser Organizer", "【百战程序员】Agent智能体开发"]
        // 真正的 Window 菜单：两个窗口标题都在（还有别的条目）
        #expect(ScriptedWindowFocus.isWindowMenu(
            itemTitles: ["Minimize", "Zoom", "", "Browser Organizer", "【百战程序员】Agent智能体开发"],
            windowTitles: windows
        ))
        // History 菜单：只回显了一个窗口标题
        #expect(!ScriptedWindowFocus.isWindowMenu(
            itemTitles: ["Home", "Browser Organizer", "Recently Closed"],
            windowTitles: windows
        ))
        // 单窗口时判据不可信，直接拒绝（调用方也不该走到这里）
        #expect(!ScriptedWindowFocus.isWindowMenu(
            itemTitles: ["Browser Organizer"],
            windowTitles: ["Browser Organizer"]
        ))
    }

    /// 生成的脚本必须把标题作为字面量嵌入，且带超时保护 ——
    /// Apple Events 默认超时两分钟，卡住的应用不能拖住 Orbit。
    @Test func appleScriptCarriesEscapedTitleAndTimeout() {
        let script = ScriptedWindowFocus.script(
            bundleIdentifier: "com.google.Chrome",
            title: #"A "B" C"#
        )
        #expect(script.contains(#"application id "com.google.Chrome""#))
        #expect(script.contains(#"A \"B\" C"#))
        #expect(script.contains("with timeout of"))
    }

}
