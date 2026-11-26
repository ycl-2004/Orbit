//
//  OrbitRingViewModel.swift
//  Orbit
//
//  The ring deliberately separates selection from activation. A card click or
//  hover selects an app; activation happens on Enter, on release of the trigger
//  key, or on a click of the center — which performs whatever it is currently
//  labelled with: Cancel with nothing selected, Confirm with an app selected.
//  The drag-owned center states (quit, cleanup, share, trash) belong to their
//  gesture and ignore clicks entirely.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum OrbitPreviewState: Equatable {
    case idle
    case loading
    case ready
    case orbit
    case screenRecordingRequired
    case noOpenWindows
    case unavailable
}

@MainActor
final class OrbitRingViewModel: ObservableObject {
    @Published private(set) var apps: [AppRecord]
    @Published var selectedID: String?
    @Published var draggedAppID: String?
    @Published var dragOffset: CGSize = .zero
    @Published var dragOverCenter = false
    /// 正在退出、消散动画还没放完的卡片。
    ///
    /// They can no longer be selected: releasing the trigger on one would hand
    /// `bringToFront` an app that is on its way out, and that relaunches it.
    @Published private(set) var departingAppIDs: Set<String> = []
    @Published var fileDropPhase: DropLifecycle = .resting
    @Published var fileTrashReady = false
    /// 上一次拖放没做成，中心正在把这件事说出来。
    @Published private(set) var fileDropFailed = false
    @Published private(set) var previews: [WindowPreview] = []
    @Published private(set) var previewState: OrbitPreviewState = .idle
    /// Which of the selected app's windows the arrow keys point at.
    @Published var selectedWindowIndex = 0
    /// 环正在收回中心，窗口马上就撤。
    ///
    /// Only ever set on the cancel path. Spatial consistency says a thing should
    /// leave the way it arrived, but paying for that on the switch path would
    /// mean the ring is still on screen, over the app the user just chose, for
    /// as long as the collapse lasts — a latency the gesture cannot afford.
    /// Cancelling has nowhere to be, so it can afford to put the cards back.
    @Published private(set) var isCollapsing = false

    var onCancel: (() -> Void)?
    /// Second argument is the window to switch to, when one was picked.
    var onActivate: ((AppRecord, WindowTarget?) -> Void)?

    private var fileTrashTask: DispatchWorkItem?
    private var dragExitTask: DispatchWorkItem?
    private var fileFailureTask: DispatchWorkItem?
    /// 触发键松开（或按了 Esc）时，环正被一个手势占着：先记下来，手势落地再关。
    ///
    /// A card being dragged and a file drop in flight both own the ring until
    /// they come to rest. A release that arrives in the middle used to be
    /// either dropped — the trigger-up event is one-shot, so the ring stayed
    /// on screen with nothing left to close it — or remembered by only one of
    /// several timers, and lost when another drag cancelled that timer. One
    /// flag, checked every time a gesture comes to rest, covers all of them.
    private var dismissalPending = false
    /// Cursor position that hover must move away from before it can select.
    /// This starts at the moment the ring opens, so the card underneath the
    /// pointer does not become selected just because the panel appeared there.
    private var hoverAnchor: CGPoint?
    /// Where the selection stood when it was cleared, so arrowing again picks
    /// up from there instead of starting over.
    private var resumeIndex: Int?
    private var bulkCleanupAttemptedIDs: Set<String> = []
    private var bulkCleanupPendingIDs: Set<String> = []
    private var bulkCleanupSucceededIDs: Set<String> = []

    /// Captured once per showing: the layout flips and the panel resizes
    /// around this, so it must not change while the ring is on screen.
    let showsPreview: Bool
    /// Captured once per showing so changing Settings cannot alter a ring that
    /// is already on screen.
    let opensInstantly: Bool

    /// Read once per showing, like `showsPreview`: the glow must not appear or
    /// vanish underneath a fan that is already on screen.
    let showsBackdrop = OrbitPreferences.ringBackdropEnabled

    /// 环按多少张卡排版。唤出时定下，之后退出了几个应用也不变。
    ///
    /// The panel and the scrim are sized once, when the ring opens. Deriving the
    /// radius, the angular step and the fan's recentring from the live card
    /// count meant quitting an app from the ring moved the hub away from the
    /// spot the scrim was lit for. Keeping the layout and letting the remaining
    /// cards close up the gap leaves both windows agreeing on where things are.
    let layoutCount: Int

    /// 扇面此刻该不该是展开的。窗口出现之后才展开，收起时合拢；直接显示扇形时一出现
    /// 就是展开的。圆环和召唤层各自用它，所以两边永远同进同退。
    func isDeployed(hasAppeared: Bool) -> Bool {
        !isCollapsing && (opensInstantly || hasAppeared)
    }

    /// 展开和收起用的动画。「直接显示扇形」只跳过展开；收起永远播，因为它是取消时
    /// 唯一的过渡。
    func deployAnimation(_ animation: Animation) -> Animation? {
        opensInstantly && !isCollapsing ? nil : animation
    }

    /// 圆环这一次要出现在哪块屏幕上。
    ///
    /// 光标决定去哪块屏，但尺寸以前一律问 `NSScreen.main` —— 那是"持有键盘焦点的
    /// 窗口所在屏"，而面板尺寸是在 `makeKey()` 之前算的，所以它答的永远是主屏。
    /// 副屏更大时圆环挤在一小块里，副屏更小时面板比屏还宽、直接被切掉一块，而
    /// 摆放逻辑却老老实实用的是光标所在屏。两边必须问同一块屏。
    let visibleFrame: CGRect
    /// 目标屏的像素密度。截图按它取样：在 1x 外接屏上按 2x 截是白烧一倍内存，
    /// 在 2x 屏上按 1x 截是糊。
    let backingScaleFactor: CGFloat

    /// 唤出那一刻用户正看着的那扇窗，预览面板会把它藏起来。
    let currentWindow: CurrentWindow?
    /// Recent windows of the frontmost app, newest first. The current window is
    /// included in the history but hidden from the carousel, leaving the last
    /// sibling as its first target.
    let recentCurrentAppWindowIDs: [CGWindowID]
    /// Synchronous target used when the trigger is released before thumbnail
    /// capture finishes (or when previews are disabled).
    let preferredCurrentAppWindow: WindowTarget?

    /// - Parameter preselecting: 唤出时就选中的应用，`nil` 表示以取消态开场。
    ///   由调用方决定，因为"最近用过的是谁"是应用列表那边的知识，而不是环的。
    init(
        apps: [AppRecord],
        showsPreview: Bool? = nil,
        screen: NSScreen? = nil,
        preselecting: String? = nil,
        currentWindow: CurrentWindow? = nil,
        recentCurrentAppWindowIDs: [CGWindowID] = [],
        preferredCurrentAppWindow: WindowTarget? = nil
    ) {
        self.currentWindow = currentWindow
        self.recentCurrentAppWindowIDs = recentCurrentAppWindowIDs
        self.preferredCurrentAppWindow = preferredCurrentAppWindow
        let target = screen ?? NSScreen.main
        self.visibleFrame = target?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        self.backingScaleFactor = target?.backingScaleFactor ?? 2

        let sourceApps = OrbitPreferences.showOrbitCard ? apps : apps.filter { !$0.isOrbit }
        let limited = Array(sourceApps.prefix(OrbitPreferences.maxVisibleApps))
        let ringApps: [AppRecord]
        if let orbit = sourceApps.first(where: { $0.isOrbit }), !limited.contains(where: { $0.isOrbit }), !limited.isEmpty {
            ringApps = Array(limited.dropLast()) + [orbit]
        } else {
            ringApps = limited
        }
        self.apps = ringApps
        self.layoutCount = ringApps.count
        self.showsPreview = showsPreview
            ?? OrbitPreferences.windowPreviewEnabled
        self.opensInstantly = OrbitPreferences.instantRingOpening
        // The ring is positioned around the current pointer. SwiftUI can emit
        // an initial `onHover` as soon as the panel appears, even though the
        // user has not moved the pointer. Treat that first location as an
        // anchor so the opening state remains whatever it opened as.
        self.hoverAnchor = NSEvent.mouseLocation

        // 只认真的在环上的卡片：预选一个被截断掉的应用，会让中心显示确认态，
        // 松手却什么都切不过去。
        if let preselecting, self.apps.contains(where: { $0.id == preselecting }) {
            self.selectedID = preselecting
        }
    }

    var selectedApp: AppRecord? {
        guard let selectedID else { return nil }
        return apps.first(where: { $0.id == selectedID })
    }

    /// 选中的是环上的第几张卡 —— 轨道上的落点要靠它知道该点亮哪一颗。
    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return apps.firstIndex(where: { $0.id == selectedID })
    }

    /// 一个还没有选中项的环，第一次按方向键该落在哪张卡上。
    ///
    /// The Orbit card is a cleanup affordance rather than a switch destination —
    /// confirming it only dismisses the ring — so entry skips it whenever a real
    /// target exists. This is the same rule `OrbitWindowController` applies when
    /// Quick switch preselects on open; keyboard entry and quick switch must
    /// agree, or releasing the trigger would do something different depending on
    /// which of the two put the highlight there.
    var entryCardID: String? {
        Self.entryCardID(in: apps.filter { isSelectable($0) })
    }

    /// 规则本身。Quick switch 在环建出来之前就要用它决定预选谁。
    static func entryCardID(in apps: [AppRecord]) -> String? {
        (apps.first(where: { !$0.isOrbit }) ?? apps.first)?.id
    }

    var centerMode: OrbitCenterMode {
        if draggedAppID != nil && dragOverCenter {
            return apps.first(where: { $0.id == draggedAppID })?.isOrbit == true ? .cleanup : .quit
        }
        if fileDropFailed {
            return .failed
        }
        if fileTrashReady {
            return .trash
        }
        if fileDropPhase.acceptsHover {
            return .share
        }
        if selectedID != nil {
            return .confirm
        }
        return .cancel
    }

    func select(_ app: AppRecord) {
        guard draggedAppID == nil, !isCollapsing, isSelectable(app) else { return }
        hoverAnchor = nil
        resumeIndex = nil
        selectedID = app.id
    }

    /// Hovering re-selects a card, which would undo an explicit deselect or
    /// select a card as soon as the ring opens under a stationary cursor.
    /// Ignore hover until the pointer actually moves away from the anchor.
    func selectFromHover(_ app: AppRecord) {
        if let anchor = hoverAnchor {
            let now = NSEvent.mouseLocation
            guard hypot(now.x - anchor.x, now.y - anchor.y) > 4 else { return }
        }
        select(app)
    }

    /// Reloads thumbnails for whatever is selected. Cancelling the previous
    /// call is what keeps a fast hover sweep from queueing captures.
    func loadPreviews() async {
        guard showsPreview, let app = selectedApp else {
            previews = []
            previewState = .idle
            return
        }

        previews = []
        selectedWindowIndex = 0

        if app.isOrbit {
            previewState = .orbit
            return
        }

        guard WindowPreviewService.hasScreenRecordingPermission() else {
            previewState = .screenRecordingRequired
            return
        }

        previewState = .loading
        let captured = await WindowPreviewService.shared
            .previews(
                forProcessIdentifier: app.processIdentifier,
                scale: backingScaleFactor,
                hiding: currentWindow?.hiddenWindow(inAppWith: app.processIdentifier),
                preferredWindowIDs: app.processIdentifier == currentWindow?.processIdentifier
                    ? recentCurrentAppWindowIDs
                    : [],
                // 每截好一扇就摆上去，而不是等整轮跑完。一扇要走 SCStream 的全屏
                // 窗能把整轮拖到两秒，而触发键往往在那之前就松开了。
                onPartial: { [weak self] partial in
                    guard let self, !Task.isCancelled else { return }
                    self.publish(partial)
                }
            )
        guard !Task.isCancelled else { return }

        publish(captured)
        if previews.isEmpty {
            if let owners = WindowServerInspector.windowOwners() {
                previewState = owners.contains(app.processIdentifier)
                    ? .unavailable
                    : .noOpenWindows
            } else {
                previewState = .unavailable
            }
        } else {
            previewState = .ready
        }
    }

    /// 把一份结果摆上面板，中途的和最终的走同一条路。
    ///
    /// 第一份中间结果一到就切出 `.loading`：面板已经有图可看了，还挂着转圈只是
    /// 让人多等一拍。真正空手而归的情况由 `loadPreviews` 收尾时处理。
    ///
    /// 选中的是「那扇窗」而不是「第几张」：最终结果可能比中途的少（空白窗被筛掉），
    /// 只按下标记，面板高亮的和松手切过去的就会是两扇不同的窗。
    private func publish(_ captured: [WindowPreview]) {
        let selectedWindowID = previews.indices.contains(selectedWindowIndex)
            ? previews[selectedWindowIndex].target.id
            : nil
        previews = Array(captured.prefix(OrbitPreferences.maxVisiblePreviews))
        if let selectedWindowID, let index = previews.firstIndex(where: { $0.target.id == selectedWindowID }) {
            selectedWindowIndex = index
        } else if !previews.indices.contains(selectedWindowIndex) {
            selectedWindowIndex = 0
        }
        if !previews.isEmpty {
            previewState = .ready
        }
    }

    func moveWindowSelection(step: Int) {
        guard previews.count > 1 else { return }
        selectedWindowIndex = (selectedWindowIndex + step + previews.count) % previews.count
    }

    /// The window the arrow keys landed on, if the app had any to choose
    /// between.
    var selectedWindowTarget: WindowTarget? {
        if previews.indices.contains(selectedWindowIndex) {
            return previews[selectedWindowIndex].target
        }
        guard let selectedApp, !selectedApp.isOrbit else { return nil }
        // 截图量出来的空白窗（比如微信那扇什么都不画的壳）对每个应用都要躲开，
        // 不只是当前应用 —— 松手比截图快的时候，这里就是唯一的判断。
        let knownBlank = WindowPreviewService.shared.knownBlankWindows
        return Self.windowTargetWithoutCapture(
            for: selectedApp,
            currentWindow: currentWindow,
            preferredCurrentAppWindow: preferredCurrentAppWindow,
            recentWindowIDs: AppActivationHistory.shared.recentWindowIDs(for: selectedApp.id),
            lookup: { pid, excluded, preferred in
                WindowServerInspector.mostRecentOtherWindow(
                    ownedBy: pid,
                    excluding: excluded,
                    preferredIDs: preferred,
                    knownBlank: knownBlank
                )
            }
        )
    }

    /// 预览还没截完时，这次切换要落到哪扇窗上。
    ///
    /// 「切到哪扇窗」只需要窗口号、标题和位置，窗口服务同步就能给；缩略图是给人
    /// 看的，跟切得准不准没有关系。可是从选中卡片到松开触发键往往只有几百毫秒，
    /// 而截图要慢得多——一扇在别的 Space 上的全屏窗就得走 `SCStream`，单扇最多两
    /// 秒。原先只有「你此刻就在的那个应用」备了这条同步答案，别的应用一律返回
    /// nil，于是松手快一点，整次切换就退化成普通的应用激活：切到了 Chrome，落在
    /// 它自己记得的那扇窗上，而不是你选的那扇。这个偶发正是它。
    ///
    /// `nonisolated` 且参数全部传入（包括去问窗口服务的 `lookup`），纯粹是为了能被
    /// 单测直接调用。
    nonisolated static func windowTargetWithoutCapture(
        for app: AppRecord,
        currentWindow: CurrentWindow?,
        preferredCurrentAppWindow: WindowTarget?,
        recentWindowIDs: [CGWindowID],
        lookup: (pid_t, CGWindowID?, [CGWindowID]) -> WindowTarget?
    ) -> WindowTarget? {
        // 当前应用那条答案是唤出的一瞬间算好的——那时 Orbit 的面板还没进窗口表，
        // 「你正看着哪一扇」还问得出来。现在再算就晚了，所以直接用它。
        if app.processIdentifier == currentWindow?.processIdentifier {
            return preferredCurrentAppWindow
        }
        // 别的应用没有「正看着的那一扇」要躲开，它的每一扇窗都是合法目的地。
        return lookup(app.processIdentifier, nil, recentWindowIDs)
    }

    /// Dismissal destroys the model, but clearing transient selection first
    /// makes the invariant explicit and prevents a retained callback or view
    /// update from observing the old Confirm state after the panel is gone.
    func resetForDismissal() {
        selectedID = nil
        selectedWindowIndex = 0
        previews = []
        previewState = .idle
        resumeIndex = nil
        isCollapsing = false
        dismissalPending = false
        // A quit that finishes after the ring is gone still runs its completion
        // against this model. Disconnecting here keeps it from cancelling
        // whichever ring the controller is showing by then.
        onCancel = nil
        onActivate = nil
    }

    /// 让卡片沿着来时的路收回中心。调用方负责在动画走完之后撤掉窗口。
    ///
    /// From here on the ring only waits to be torn down. The trigger is still
    /// tracked as held for the length of the collapse, so a release, an Enter
    /// or a hub click can all still arrive — and with the old selection still
    /// standing, they used to switch to the app the user had just cancelled.
    /// Every entry point that acts on the ring checks `isCollapsing` first.
    func beginCollapse() {
        isCollapsing = true
        dismissalPending = false
    }

    private func isSelectable(_ app: AppRecord) -> Bool {
        !departingAppIDs.contains(app.id)
    }

    func moveSelection(step: Int) {
        guard !isCollapsing, apps.contains(where: { isSelectable($0) }) else { return }

        // After an explicit deselect, the first arrow press returns to the card
        // that was left, rather than jumping back to the start of the ring.
        if selectedID == nil, let resumeIndex, apps.indices.contains(resumeIndex), isSelectable(apps[resumeIndex]) {
            self.resumeIndex = nil
            hoverAnchor = nil
            selectedID = apps[resumeIndex].id
            return
        }

        // A neutral ring has no meaningful “backward” edge. Apple, Windows,
        // VS Code and JetBrains switchers enter through their first MRU target;
        // make both arrow directions share that predictable first step.
        if selectedID == nil {
            hoverAnchor = nil
            selectedID = entryCardID
            return
        }

        let currentIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) } ?? 0
        var nextIndex = currentIndex
        repeat {
            nextIndex = (nextIndex + step + apps.count) % apps.count
        } while !isSelectable(apps[nextIndex]) && nextIndex != currentIndex
        selectedID = apps[nextIndex].id
    }

    func select(number: String) {
        guard !isCollapsing,
              let number = Int(number), number > 0, number <= apps.count,
              isSelectable(apps[number - 1]) else { return }
        selectedID = apps[number - 1].id
    }

    func select(letter: String) {
        guard !isCollapsing, !apps.isEmpty, let first = letter.first else { return }
        let startIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) } ?? -1
        let orderedIndices = Array(0 ..< apps.count).map { (startIndex + 1 + $0) % apps.count }
        let wanted = Character(String(first).uppercased())
        guard let match = orderedIndices.first(where: {
            isSelectable(apps[$0]) && apps[$0].letterShortcut == wanted
        }) else {
            return
        }
        selectedID = apps[match].id
    }

    func confirmSelection() {
        guard !isCollapsing else { return }
        guard let selectedApp, isSelectable(selectedApp) else {
            onCancel?()
            return
        }

        // Orbit has no ordinary application window to activate. Selecting its
        // card simply dismisses the ring; dragging it to the center is the
        // explicit cleanup gesture handled in `finishAppDrag` below.
        if selectedApp.isOrbit {
            onCancel?()
            return
        }

        onActivate?(selectedApp, selectedWindowTarget)
    }

    /// Clears the highlight so releasing the trigger dismisses the ring
    /// instead of switching apps.
    func deselect() {
        guard draggedAppID == nil, !isCollapsing else { return }
        resumeIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) }
        selectedID = nil
        hoverAnchor = NSEvent.mouseLocation
    }

    /// 一张卡片正被拖着，或者一次文件拖放还没落地：这时环归那个手势管。
    private var gestureOwnsRing: Bool {
        draggedAppID != nil || fileDropPhase != .resting
    }

    /// 手势落地之后，兑现它进行期间收到的那次「关」。
    private func dismissIfPending() {
        guard dismissalPending, !gestureOwnsRing, !isCollapsing else { return }
        dismissalPending = false
        onCancel?()
    }

    /// 关闭圆环 —— 除非有手势还没落地。
    ///
    /// Dismissing releases the panel and with it this view model, and the
    /// completion handler that finishes a drop holds `self` weakly. So an
    /// Escape pressed in the moment between letting the files go and the URLs
    /// coming back used to make the AirDrop or the move to Trash disappear
    /// without a trace — the files looked dropped and nothing happened. Record
    /// the intent instead; whichever gesture owns the ring closes it once it
    /// has reached a stable state.
    func cancel() {
        guard !isCollapsing else { return }
        guard !gestureOwnsRing else {
            dismissalPending = true
            return
        }
        onCancel?()
    }

    /// 点中心那颗按钮把选中的 App 切过去，跟松开触发键是同一件事。
    ///
    /// Guarded like `cancel()`: a card in flight or a file drop in progress owns
    /// the hub, and a stray tap must not switch apps out from under either of
    /// them. Unlike a cancel this is not deferred — switching apps is not what
    /// the user was in the middle of, and `.processing` lasts a few frames.
    func confirmFromHub() {
        guard !gestureOwnsRing else { return }
        confirmSelection()
    }

    /// 松开触发键。手势进行中松开的，不切换：等手势落地后直接关环。
    func triggerReleased() {
        guard !isCollapsing else { return }
        guard !gestureOwnsRing else {
            dismissalPending = true
            return
        }
        if selectedID == nil {
            onCancel?()
        } else {
            confirmSelection()
        }
    }

    func beginAppDrag(_ app: AppRecord) {
        selectedID = app.id
        draggedAppID = app.id
        dragOffset = .zero
        dragOverCenter = false
    }

    func updateAppDrag(_ app: AppRecord, offset: CGSize, overCenter: Bool) {
        guard draggedAppID == app.id else { return }
        dragOffset = offset
        dragOverCenter = overCenter
    }

    func finishAppDrag(_ app: AppRecord) {
        guard draggedAppID == app.id else { return }
        let shouldQuit = dragOverCenter
        draggedAppID = nil
        dragOffset = .zero
        dragOverCenter = false
        // 拖动途中松开了触发键：退出请求照常发出，环在这一刻关掉。
        defer { dismissIfPending() }

        guard shouldQuit else { return }

        selectedID = nil

        if app.isOrbit {
            cleanupWindowlessApps()
            return
        }

        beginDeparture(of: [app.id])
        app.requestQuit { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                guard success else {
                    self.departingAppIDs.remove(app.id)
                    return
                }

                // 宽限期比消散动画短，所以退出成功之后还要把动画剩下的那一截等完
                // 再抽走卡片 —— 否则碎片飞到一半，卡片就凭空不见了。
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.dispersionRemainder) {
                    self.finishDeparture(removing: [app.id], settling: [app.id])
                    if self.apps.isEmpty {
                        self.onCancel?()
                    }
                }
            }
        }
    }

    /// 这些卡片开始消散：从现在起不能再被选中。
    func beginDeparture(of ids: Set<String>) {
        departingAppIDs.formUnion(ids)
    }

    /// 退出宽限期结束之后，消散动画还剩多少没放完。
    private static var dispersionRemainder: TimeInterval {
        max(0, OrbitPreferences.dispersionDuration - OrbitPreferences.quitGracePeriod)
    }

    /// 把退出成功的卡片拿下环，剩下的卡片顺着补位。
    ///
    /// - Parameters:
    ///   - departed: Apps that actually quit; their cards leave the ring.
    ///   - settled: Every app this departure was waiting on, including any
    ///     that refused to quit — those cards become selectable again.
    private func finishDeparture(removing departed: Set<String>, settling settled: Set<String>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            apps.removeAll { departed.contains($0.id) }
            departingAppIDs.subtract(settled)
        }
    }

    /// Requests a normal quit for the cards that are truly windowless. A blank
    /// preview is deliberately not enough: capture can fail while a real app
    /// window still exists. Finder and Orbit are never candidates.
    private func cleanupWindowlessApps() {
        guard let windowedPIDs = WindowServerInspector.windowOwners() else {
            // Keep the ring alive while the trigger is held. An unavailable
            // window list means "nothing can be safely cleaned", not "the
            // user asked to dismiss Orbit".
            return
        }

        let candidates = apps.filter { app in
            !app.isOrbit && !app.isFinder && !windowedPIDs.contains(app.processIdentifier)
        }
        guard !candidates.isEmpty else {
            // Orbit itself is intentionally not a cleanup candidate. Leave
            // the ring visible so releasing the trigger remains the only
            // dismissal path for this gesture.
            return
        }

        selectedID = nil
        bulkCleanupAttemptedIDs = Set(candidates.map(\.id))
        bulkCleanupPendingIDs = bulkCleanupAttemptedIDs
        bulkCleanupSucceededIDs = []
        beginDeparture(of: bulkCleanupAttemptedIDs)

        for app in candidates {
            app.requestQuit { [weak self] success in
                DispatchQueue.main.async {
                    self?.finishBulkCleanup(for: app.id, succeeded: success)
                }
            }
        }
    }

    private func finishBulkCleanup(for appID: String, succeeded: Bool) {
        guard bulkCleanupPendingIDs.remove(appID) != nil else { return }
        if succeeded {
            bulkCleanupSucceededIDs.insert(appID)
        }
        guard bulkCleanupPendingIDs.isEmpty else { return }

        let succeededIDs = bulkCleanupSucceededIDs
        let attemptedIDs = bulkCleanupAttemptedIDs
        bulkCleanupAttemptedIDs = []
        bulkCleanupSucceededIDs = []
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dispersionRemainder) { [weak self] in
            // Do not dismiss after the Orbit cleanup gesture. The trigger key
            // is still held at this point; `triggerReleased()` will close the
            // ring when the user intentionally lets go.
            self?.finishDeparture(removing: succeededIDs, settling: attemptedIDs)
        }
    }

    func setFileDragTargeted(_ targeted: Bool) {
        if targeted {
            dragExitTask?.cancel()
            dragExitTask = nil
            fileTrashTask?.cancel()
            // A new drag is a new question; the previous drop's verdict is no
            // longer what the hub should be saying.
            fileFailureTask?.cancel()
            fileFailureTask = nil
            fileDropFailed = false
            fileTrashReady = false
            fileDropPhase = .sharing

            let task = DispatchWorkItem { [weak self] in
                guard let self, self.fileDropPhase.acceptsHover else { return }
                self.fileTrashReady = true
                self.fileDropPhase = .trashReady
            }
            fileTrashTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + OrbitPreferences.fileTrashHoldDuration, execute: task)
        } else {
            fileTrashTask?.cancel()
            fileTrashTask = nil
            scheduleDragExitReset()
        }
    }

    /// 拖拽离开中心时把状态复位 —— 但要晚一拍。
    ///
    /// SwiftUI reports "no longer targeted" and "here are the dropped items" as
    /// two separate callbacks whose order is not guaranteed, and `handleFileDrop`
    /// needs `fileTrashReady` to still be standing when it runs. So the exit path
    /// arms a short-fuse reset that a real drop cancels, instead of resetting on
    /// the spot.
    ///
    /// Resetting must happen *somehow*, though: this used to bail out whenever the
    /// the trash was ready, which left `fileDropPhase` stuck on `.trashReady` after a
    /// drag that hovered long enough and then left without dropping. Both `cancel()`
    /// and `triggerReleased()` require `.resting`, so the ring became impossible to
    /// dismiss.
    private func scheduleDragExitReset() {
        dragExitTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self, self.fileDropPhase != .processing else { return }
            self.fileTrashReady = false
            self.fileDropPhase = .resting
            self.dismissIfPending()
        }
        dragExitTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitPreferences.fileDragExitGrace, execute: task)
    }

    /// 把「没成」挂在中心上，等它被看见了再谈关不关。
    ///
    /// A deferred dismissal is honoured *after* the notice rather than instead
    /// of it: the trigger key having been let go is no reason to close the ring
    /// on a message nobody got to read. A new drag that cuts the notice short
    /// keeps the pending dismissal; that drag honours it when it comes to rest.
    private func reportFileDropFailure() {
        fileDropFailed = true
        fileFailureTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileFailureTask = nil
            self.fileDropFailed = false
            self.dismissIfPending()
        }
        fileFailureTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + OrbitPreferences.fileDropFailureNoticeDuration,
            execute: task
        )
    }

    func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let shouldTrash = fileTrashReady
        dragExitTask?.cancel()
        dragExitTask = nil
        fileTrashTask?.cancel()
        fileTrashTask = nil
        fileDropPhase = .processing

        // 每个 provider 写自己那一格，而不是一起往同一个数组尾部挤。
        //
        // `loadDataRepresentation` calls back on whatever thread it likes, and
        // several providers run at once, so appending from inside those closures
        // is a data race on the array's buffer — dropping five files at once could
        // lose one or crash outright. Slots also keep the files in the order they
        // were dragged, instead of whatever order the callbacks happen to land in.
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        let collected = DroppedURLs(count: fileProviders.count)
        let group = DispatchGroup()

        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.set(url, at: index)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            // 所有 leave 都到齐了，`DispatchGroup` 保证这里读得到每一次写入。
            let urls = collected.urls

            guard let self else { return }
            self.fileTrashReady = false
            self.fileDropPhase = .resting
            guard !urls.isEmpty else {
                self.dismissIfPending()
                return
            }

            // 失败必须看得见。
            //
            // A locked file, a volume with no Trash, an AirDrop the system will
            // not offer — all of them used to end the same way as a success:
            // the ring closed and the files stayed where they were. The hub is
            // the thing the files were dropped on, so it is the thing that says
            // the drop did not take.
            var failed = false
            if shouldTrash {
                // 一个文件失败不该拖累后面的：全部试完，再报告有没有失手的。
                for url in urls {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } catch {
                        failed = true
                    }
                }
            } else if let service = NSSharingService(named: .sendViaAirDrop),
                      service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
                failed = false
            } else {
                failed = true
            }

            guard !failed else {
                self.reportFileDropFailure()
                return
            }

            // Keep the ring visible while the trigger is still held. If the
            // trigger was released during URL loading, close now that the
            // asynchronous file operation has reached a stable state.
            self.dismissIfPending()
        }

        return true
    }

    func handle(_ command: OrbitKeyboardCommand, value: String?) {
        switch command {
        case .next:
            moveSelection(step: 1)
        case .previous:
            moveSelection(step: -1)
        case .activate:
            confirmSelection()
        case .cancel:
            cancel()
        case .deselect:
            deselect()
        case .nextWindow:
            moveWindowSelection(step: 1)
        case .previousWindow:
            moveWindowSelection(step: -1)
        case .number:
            guard OrbitPreferences.numericShortcutsEnabled, let value else { return }
            select(number: value)
        case .letter:
            guard OrbitPreferences.letterShortcutsEnabled, let value else { return }
            select(letter: value)
        }
    }
}

/// 一次拖放里收集到的文件 URL，按拖入顺序摆好。
///
/// One slot per provider, so the callbacks never touch the same element and the
/// result keeps the drag's order. The lock guards the array's own storage, which
/// concurrent writes to different indices would still race on.
nonisolated private final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ url: URL, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard slots.indices.contains(index) else { return }
        slots[index] = url
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

enum OrbitCenterMode: CaseIterable {
    case cancel
    case confirm
    case quit
    case cleanup
    case share
    case trash
    /// 刚才那次拖放没做成。
    case failed

    /// 每个模式一个图标，而且要能自己说清自己是什么。
    ///
    /// `.quit` and `.trash` used to share `circle.dashed`, which meant the two
    /// most destructive states on the ring — quit this app, throw these files
    /// away — were drawn identically, and neither was drawn as the thing it did.
    /// `.share` is specifically an AirDrop, so it gets the radiating glyph rather
    /// than the generic share-sheet arrow; there is no AirDrop SF Symbol, and the
    /// system's own AirDrop artwork is a full-colour rounded tile that cannot sit
    /// inside a tinted circle.
    var iconName: String {
        switch self {
        case .cancel: "xmark"
        case .confirm: "arrow.right"
        case .quit: "power"
        case .cleanup: "sparkles"
        case .trash: "trash"
        case .share: "dot.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        }
    }
}
