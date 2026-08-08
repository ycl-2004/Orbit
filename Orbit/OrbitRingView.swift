//
//  OrbitRingView.swift
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
    @Published var vanishingAppID: String?
    @Published private(set) var bulkVanishingAppIDs: Set<String> = []
    @Published var fileDropPhase: DropLifecycle = .resting
    @Published var fileTrashReady = false
    /// 上一次拖放没做成，中心正在把这件事说出来。
    @Published private(set) var fileDropFailed = false
    @Published private(set) var previews: [WindowPreview] = []
    @Published private(set) var isLoadingPreviews = false
    @Published private(set) var previewState: OrbitPreviewState = .idle
    /// Which of the selected app's windows the arrow keys point at.
    @Published var selectedWindowIndex = 0

    var onCancel: (() -> Void)?
    /// Second argument is the window to switch to, when one was picked.
    var onActivate: ((AppRecord, WindowTarget?) -> Void)?

    private var fileTrashTask: DispatchWorkItem?
    private var dragExitTask: DispatchWorkItem?
    private var fileFailureTask: DispatchWorkItem?
    /// A trigger release can arrive while the dropped URLs are still being
    /// read. Defer dismissal until that asynchronous file operation finishes.
    private var dismissAfterFileDrop = false
    /// Cursor position that hover must move away from before it can select.
    /// This starts at the moment the ring opens, so the card underneath the
    /// pointer does not become selected just because the panel appeared there.
    private var hoverAnchor: CGPoint?
    /// Where the selection stood when it was cleared, so arrowing again picks
    /// up from there instead of starting over.
    private var resumeIndex: Int?
    private var bulkCleanupPendingIDs: Set<String> = []
    private var bulkCleanupSucceededIDs: Set<String> = []

    /// Captured once per showing: the layout flips and the panel resizes
    /// around this, so it must not change while the ring is on screen.
    let showsPreview: Bool

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

        let sourceApps = OrbitConfig.showOrbitCard ? apps : apps.filter { !$0.isOrbit }
        let limited = Array(sourceApps.prefix(OrbitConfig.maxVisibleApps))
        if let orbit = sourceApps.first(where: { $0.isOrbit }), !limited.contains(where: { $0.isOrbit }), !limited.isEmpty {
            self.apps = Array(limited.dropLast()) + [orbit]
        } else {
            self.apps = limited
        }
        self.showsPreview = showsPreview
            ?? OrbitConfig.windowPreviewEnabled
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

    var ringRadius: CGFloat {
        OrbitConfig.ringRadius(cardCount: apps.count)
    }

    var canvasSize: CGFloat {
        OrbitConfig.ringCanvasSize(cardCount: apps.count)
    }

    /// The highest-value recent destination is the ring's spatial anchor: index
    /// zero always sits at 12 o'clock, upright. It is another window of the
    /// current app when available, otherwise the previous application. Stable
    /// placement matters more than centring a short fan.
    private let fanStartAngle = -Double.pi / 2

    /// MRU order walks from 12 o'clock down the left side first. The direction
    /// stays identical with and without Window Preview, so repeated keyboard
    /// steps build one spatial memory instead of mirroring the sequence.
    func angle(for index: Int) -> Double {
        let step = OrbitConfig.ringStep(cardCount: apps.count)
        return fanStartAngle - step * Double(index)
    }

    /// 开着预览时，圆环和预览各占窗口的一半，并各自停在那一半的正中间。
    ///
    /// The previous layout let the preview claim every point the fan left over
    /// and then centred the carousel inside that oversized frame. Because the
    /// ring canvas is a fixed square pinned to the window's left edge, the pair
    /// ended up sitting well left of the screen's centre line even though the
    /// window itself was centred. Two equal halves anchored to the same centre
    /// line is what puts the ring and the preview on opposite ends instead.
    var columnWidth: CGFloat {
        layoutWidth / 2
    }

    /// 窗口整体的宽度：刻意留一圈屏幕边距，不铺满。
    ///
    /// Filling the visible frame is what exiled the ring to the left corner:
    /// each half is centred on its own contents, so the wider the window, the
    /// further apart the two halves' centres sit. Holding the window to
    /// `layoutWidthRatio` of the screen keeps a real margin outside the pair,
    /// which is what lets it read as one centred object rather than a bar
    /// pinned to both edges. The centre line the two halves share is a layout
    /// reference only; nothing is ever drawn on it.
    private var layoutWidth: CGFloat {
        let visibleWidth = visibleFrame.width
        let maximum = canvasSize + OrbitConfig.previewPanelMaximumWidth + OrbitConfig.previewGap * 2
        // A full twelve-card fan makes a disc wider than the ratio leaves room
        // for, and a disc that overruns its half would sit on the carousel.
        // Widen for it rather than crop it — the ratio is there to keep the
        // ring out of the corner, not to decide how big the fan may get.
        let discDemand = (backdropDiameter + OrbitConfig.previewGap * 2) * 2
        return max(
            canvasSize,
            min(
                max(visibleWidth * OrbitConfig.layoutWidthRatio, discDemand, previewDemand),
                visibleWidth - OrbitConfig.screenMargin * 2,
                maximum
            )
        )
    }

    /// 预览想要的卡片宽度，只由屏幕和用户设的倍率决定。
    ///
    /// 刻意不看 `columnWidth`：那一半的宽度是由这个数推出来的，反过来读它就成了
    /// 环。这里量的是"在默认版式下这一半有多宽"，于是倍率 1.0 复现的正好是今天
    /// 的尺寸，一个像素不差。
    private var desiredPreviewCardWidth: CGFloat {
        let half = visibleFrame.width * OrbitConfig.layoutWidthRatio / 2
        let usable = half - OrbitConfig.previewGap * 2
        let base = min(OrbitConfig.previewCardMaximumWidth, usable / OrbitConfig.previewCarouselSpan)
        return max(120, base * OrbitConfig.previewScale)
    }

    /// 放大预览要靠窗口变宽，不然那一半装不下。
    ///
    /// 跟 `discDemand` 同一个套路：版式比例是用来把圆环从屏幕角落里拉回来的，不是
    /// 用来决定东西能有多大。缩小时不反过来收窄窗口 —— 那会让圆环跟着挪位置，
    /// 而改预览大小不该动到环。
    private var previewDemand: CGFloat {
        guard showsPreview else { return 0 }
        let half = desiredPreviewCardWidth * OrbitConfig.previewCarouselSpan + OrbitConfig.previewGap * 2
        return half * 2
    }

    /// Total size of the panel that hosts the ring, plus the preview when it
    /// is enabled.
    var panelSize: CGSize {
        guard showsPreview else {
            return CGSize(width: canvasSize, height: canvasSize)
        }
        // A short fan must not squash the carousel: the window grows past the
        // canvas when the ring alone would not give the stage room. The ring
        // stays centered in whatever height that comes to.
        let screenHeight = visibleFrame.height
        let stageHeight = previewCardWidth / OrbitConfig.previewStageAspectRatio + 120
        return CGSize(
            width: layoutWidth,
            height: min(max(canvasSize, stageHeight), screenHeight - 60)
        )
    }

    /// Width of the foreground carousel card. Driven by the half of the window
    /// the preview owns — never by the selected window — so that the stage, and
    /// with it the page control, holds still while arrowing through.
    var previewCardWidth: CGFloat {
        let usable = columnWidth - OrbitConfig.previewGap * 2
        // 想要多大是一回事，那一半真的装得下多少是另一回事：屏幕不够宽时，
        // 窗口涨不到 `previewDemand`，卡片就得让步。
        return max(120, min(desiredPreviewCardWidth, usable / OrbitConfig.previewCarouselSpan))
    }

    /// Outer diameter of the band the fan sits on, measured from the cards.
    var backdropDiameter: CGFloat {
        OrbitConfig.ringBackdropRadius(cardCount: apps.count) * 2
    }

    /// 轨道要盖住的那段角度：正好是首尾两张卡片之间，两端各多留一点。
    ///
    /// The track follows the fixed top anchor through the final card. Angles
    /// decrease as MRU order advances, while the backdrop shape expects an
    /// ascending range, so the last card supplies the lower bound.
    var backdropArc: ClosedRange<Double> {
        let span = apps.count > 1
            ? OrbitConfig.ringStep(cardCount: apps.count) * Double(apps.count - 1)
            : 0
        let padding = OrbitConfig.ringTrackEndPadding(cardCount: apps.count)
        return (fanStartAngle - span - padding)...(fanStartAngle + padding)
    }

    /// Read once per showing, like `showsPreview`: the disc must not appear or
    /// vanish underneath a fan that is already on screen.
    let showsBackdrop = OrbitConfig.ringBackdropEnabled

    func position(for index: Int) -> CGPoint {
        let center = canvasSize / 2
        guard !apps.isEmpty else {
            return CGPoint(x: center, y: center)
        }

        let angle = angle(for: index)
        return CGPoint(
            x: center + cos(angle) * ringRadius,
            y: center + sin(angle) * ringRadius
        )
    }

    func select(_ app: AppRecord) {
        guard draggedAppID == nil else { return }
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
            isLoadingPreviews = false
            previewState = .idle
            return
        }

        previews = []
        selectedWindowIndex = 0

        if app.isOrbit {
            isLoadingPreviews = false
            previewState = .orbit
            return
        }

        guard WindowPreviewService.hasScreenRecordingPermission() else {
            isLoadingPreviews = false
            previewState = .screenRecordingRequired
            return
        }

        isLoadingPreviews = true
        previewState = .loading
        let captured = await WindowPreviewService.shared
            .previews(
                forProcessIdentifier: app.processIdentifier,
                scale: backingScaleFactor,
                hiding: currentWindow?.hiddenWindow(inAppWith: app.processIdentifier),
                preferredWindowIDs: app.processIdentifier == currentWindow?.processIdentifier
                    ? recentCurrentAppWindowIDs
                    : []
            )
        guard !Task.isCancelled else { return }

        previews = Array(captured.prefix(OrbitConfig.maxVisiblePreviews))
        isLoadingPreviews = false
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
        guard selectedApp?.processIdentifier == currentWindow?.processIdentifier else {
            return nil
        }
        return preferredCurrentAppWindow
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
    }

    func moveSelection(step: Int) {
        guard !apps.isEmpty else { return }

        // After an explicit deselect, the first arrow press returns to the card
        // that was left, rather than jumping back to the start of the ring.
        if selectedID == nil, let resumeIndex, apps.indices.contains(resumeIndex) {
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
            selectedID = apps[0].id
            return
        }

        let currentIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = (currentIndex + step + apps.count) % apps.count
        selectedID = apps[nextIndex].id
    }

    func select(number: String) {
        guard let number = Int(number), number > 0, number <= apps.count else { return }
        selectedID = apps[number - 1].id
    }

    func select(letter: String) {
        guard !apps.isEmpty, let first = letter.first else { return }
        let startIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) } ?? -1
        let orderedIndices = Array(0 ..< apps.count).map { (startIndex + 1 + $0) % apps.count }
        guard let match = orderedIndices.first(where: { apps[$0].letterShortcut == Character(String(first).uppercased()) }) else {
            return
        }
        selectedID = apps[match].id
    }

    func confirmSelection() {
        guard let selectedApp else {
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
        guard draggedAppID == nil else { return }
        resumeIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) }
        selectedID = nil
        hoverAnchor = NSEvent.mouseLocation
    }

    /// 关闭圆环 —— 除非文件拖放还没落地。
    ///
    /// Dismissing releases the panel and with it this view model, and the
    /// completion handler that finishes a drop holds `self` weakly. So an
    /// Escape pressed in the moment between letting the files go and the URLs
    /// coming back used to make the AirDrop or the move to Trash disappear
    /// without a trace — the files looked dropped and nothing happened. Record
    /// the intent instead; `handleFileDrop` and the drag-exit reset both close
    /// the ring once the file work has reached a stable state.
    func cancel() {
        guard draggedAppID == nil else { return }
        guard fileDropPhase == .resting else {
            dismissAfterFileDrop = true
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
        guard draggedAppID == nil, fileDropPhase == .resting else { return }
        confirmSelection()
    }

    func triggerReleased() {
        guard draggedAppID == nil else { return }
        guard fileDropPhase == .resting else {
            dismissAfterFileDrop = true
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

        guard shouldQuit else { return }

        selectedID = nil

        if app.isOrbit {
            cleanupWindowlessApps()
            return
        }

        vanishingAppID = app.id
        app.requestQuit { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                guard success else {
                    self.vanishingAppID = nil
                    return
                }

                // 宽限期比消散动画短，所以退出成功之后还要把动画剩下的那一截等完
                // 再抽走卡片 —— 否则碎片飞到一半，卡片就凭空不见了。
                let remaining = max(0, OrbitConfig.dispersionDuration - OrbitConfig.terminateGracePeriod)
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    self.apps.removeAll { $0.id == app.id }
                    self.vanishingAppID = nil
                    if self.apps.isEmpty {
                        self.onCancel?()
                    }
                }
            }
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
        bulkCleanupPendingIDs = Set(candidates.map(\.id))
        bulkCleanupSucceededIDs = []
        bulkVanishingAppIDs = bulkCleanupPendingIDs

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
        let remaining = max(0, OrbitConfig.dispersionDuration - OrbitConfig.terminateGracePeriod)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self else { return }
            self.apps.removeAll { succeededIDs.contains($0.id) }
            self.bulkVanishingAppIDs = []
            self.bulkCleanupSucceededIDs = []
            // Do not dismiss after the Orbit cleanup gesture. The trigger key
            // is still held at this point; `triggerReleased()` will close the
            // ring when the user intentionally lets go.
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
            DispatchQueue.main.asyncAfter(deadline: .now() + OrbitConfig.fileTrashHoldDuration, execute: task)
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
            if self.dismissAfterFileDrop {
                self.dismissAfterFileDrop = false
                self.onCancel?()
            }
        }
        dragExitTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitConfig.fileDragExitGrace, execute: task)
    }

    /// 把「没成」挂在中心上，等它被看见了再谈关不关。
    ///
    /// A deferred dismissal is honoured *after* the notice rather than instead
    /// of it: the trigger key having been let go is no reason to close the ring
    /// on a message nobody got to read.
    private func reportFileDropFailure(thenDismiss shouldDismiss: Bool) {
        fileDropFailed = true
        fileFailureTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileFailureTask = nil
            self.fileDropFailed = false
            if shouldDismiss {
                self.onCancel?()
            }
        }
        fileFailureTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + OrbitConfig.fileDropFailureNoticeDuration,
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
            let shouldDismiss = self.dismissAfterFileDrop
            self.dismissAfterFileDrop = false
            guard !urls.isEmpty else {
                if shouldDismiss {
                    self.onCancel?()
                }
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
                self.reportFileDropFailure(thenDismiss: shouldDismiss)
                return
            }

            // Keep the ring visible while the trigger is still held. If the
            // trigger was released during URL loading, close now that the
            // asynchronous file operation has reached a stable state.
            if shouldDismiss {
                self.onCancel?()
            }
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
            guard OrbitConfig.numericShortcutsEnabled, let value else { return }
            select(number: value)
        case .letter:
            guard OrbitConfig.letterShortcutsEnabled, let value else { return }
            select(letter: value)
        }
    }
}

/// 一次拖放里收集到的文件 URL，按拖入顺序摆好。
///
/// One slot per provider, so the callbacks never touch the same element and the
/// result keeps the drag's order. The lock guards the array's own storage, which
/// concurrent writes to different indices would still race on.
private final class DroppedURLs: @unchecked Sendable {
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

struct OrbitRingView: View {
    @ObservedObject var model: OrbitRingViewModel

    @State private var hasAppeared = false

    var body: some View {
        layout
            .frame(width: model.panelSize.width, height: model.panelSize.height)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasAppeared)
            .onAppear { hasAppeared = true }
    }

    /// Two equal halves rather than an HStack sized by its contents. The ring
    /// canvas and the preview are very different widths, and letting either one
    /// absorb the leftover space is what pulled the pair off the screen's
    /// centre line; giving each the same half puts them on opposite ends of it.
    @ViewBuilder
    private var layout: some View {
        if model.showsPreview {
            HStack(spacing: 0) {
                ringCanvas
                    .frame(width: model.columnWidth)

                OrbitPreviewPanel(model: model)
                    .frame(width: model.columnWidth)
            }
        } else {
            ringCanvas
        }
    }

    private var ringCanvas: some View {
        ZStack {
            if model.showsBackdrop {
                OrbitRingBackdrop(
                    radius: model.ringRadius,
                    thickness: OrbitConfig.ringTrackThickness,
                    arc: model.backdropArc,
                    tint: OrbitPalette.backdrop
                )
                .position(
                    x: model.canvasSize / 2,
                    y: model.canvasSize / 2
                )
                .zIndex(-1)
            }

            ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                let basePosition = model.position(for: index)
                OrbitAppCard(
                    app: app,
                    cardNumber: index + 1,
                    angle: model.angle(for: index),
                    isSelected: model.selectedID == app.id,
                    isDragging: model.draggedAppID == app.id,
                    isVanishing: model.vanishingAppID == app.id || model.bulkVanishingAppIDs.contains(app.id),
                    dragOffset: model.draggedAppID == app.id ? model.dragOffset : .zero,
                    onSelect: { model.select(app) },
                    onHoverSelect: { model.selectFromHover(app) },
                    onDragChanged: { offset in
                        if model.draggedAppID != app.id {
                            model.beginAppDrag(app)
                        }
                        let draggedCenter = CGPoint(
                            x: basePosition.x + offset.width,
                            y: basePosition.y + offset.height
                        )
                        let center = CGPoint(
                            x: model.canvasSize / 2,
                            y: model.canvasSize / 2
                        )
                        let distance = hypot(draggedCenter.x - center.x, draggedCenter.y - center.y)
                        model.updateAppDrag(
                            app,
                            offset: offset,
                            overCenter: distance <= OrbitConfig.centerRadius + 28
                        )
                    },
                    onDragEnded: { model.finishAppDrag(app) }
                )
                .position(basePosition)
                // A lifted card must never slide underneath its neighbours.
                .zIndex(model.draggedAppID == app.id ? 2 : (model.selectedID == app.id ? 1 : 0))
            }

            OrbitCenterControl(
                mode: model.centerMode,
                isFileTargeted: Binding(
                    get: { model.fileDropPhase.acceptsHover },
                    set: { model.setFileDragTargeted($0) }
                ),
                onCancel: { model.cancel() },
                onConfirm: { model.confirmFromHub() },
                onDrop: { providers in model.handleFileDrop(providers) }
            )
            .position(
                x: model.canvasSize / 2,
                y: model.canvasSize / 2
            )
            .zIndex(3)
        }
        .frame(width: model.canvasSize, height: model.canvasSize)
        .background(Color.clear)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.selectedID)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.centerMode)
    }
}

/// A compact carousel of every window belonging to the selected app. The
/// selected window stays in front while its neighbours peek out on either
/// side, matching the way a person scans a small stack of related screens.
private struct OrbitPreviewPanel: View {
    @ObservedObject var model: OrbitRingViewModel

    private var selectedIndex: Int {
        guard model.previews.indices.contains(model.selectedWindowIndex) else { return 0 }
        return model.selectedWindowIndex
    }

    private var cardSize: CGSize {
        let width = model.previewCardWidth
        return CGSize(
            width: width,
            height: (width / OrbitConfig.previewStageAspectRatio).rounded()
        )
    }

    var body: some View {
        Group {
            switch model.previewState {
            case .idle:
                statusCard(
                    systemName: "square.grid.2x2",
                    titleKey: "preview.empty.title",
                    messageKey: "preview.empty.message"
                )
            case .loading:
                statusCard(
                    systemName: "rectangle.inset.filled",
                    titleKey: "preview.loading.title",
                    messageKey: "preview.loading.message",
                    showsProgress: true
                )
            case .ready:
                carousel
            case .orbit:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.orbit.title",
                    messageKey: "preview.orbit.message",
                    hintKey: "preview.orbit.hint"
                )
            case .screenRecordingRequired:
                statusCard(
                    systemName: "lock.shield",
                    titleKey: "preview.permission.title",
                    messageKey: "preview.permission.message",
                    actionKey: "preview.permission.action",
                    action: SystemSettingsLink.screenRecording.open
                )
            case .noOpenWindows:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.noWindows.title",
                    messageKey: "preview.noWindows.message"
                )
            case .unavailable:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.unavailable.title",
                    messageKey: "preview.unavailable.message"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: model.previews.map(\.id))
        .animation(.easeOut(duration: 0.14), value: model.selectedWindowIndex)
        // Re-running on identity cancels the in-flight capture when the
        // selection moves on, which is the whole debounce we need.
        .task(id: model.selectedID) {
            await model.loadPreviews()
        }
    }

    private var carousel: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(model.previews.enumerated()), id: \.element.id) { index, preview in
                    if let position = deckPosition(for: index) {
                        OrbitPreviewWindowCard(
                            preview: preview,
                            isSelected: index == selectedIndex
                        )
                        .frame(width: cardSize.width, height: cardSize.height)
                        .scaleEffect(position.scale)
                        .offset(position.offset)
                        .opacity(position.opacity)
                        .zIndex(position.zIndex)
                        .onTapGesture { model.selectedWindowIndex = index }
                    }
                }
            }
            .frame(height: cardSize.height + 24)

            if model.previews.count > 1 {
                windowControls
            }
        }
    }

    private var windowControls: some View {
        HStack(spacing: 6) {
            windowStep(systemName: "chevron.left", step: -1)

            Text("\(selectedIndex + 1) / \(model.previews.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 46)

            windowStep(systemName: "chevron.right", step: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
    }

    /// A plain tap target rather than a `Button`: the ring window takes key
    /// focus, and a focusable control there would answer Return before the
    /// selected app does.
    private func windowStep(systemName: String, step: Int) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
            .onTapGesture { model.moveWindowSelection(step: step) }
    }

    /// Only the immediate neighbours are drawn. A deeper stack turns into
    /// clutter well before it helps anyone tell two windows apart.
    private func deckPosition(for index: Int) -> (offset: CGSize, scale: CGFloat, opacity: Double, zIndex: Double)? {
        let sideOffset = cardSize.width * OrbitConfig.previewSideOffsetRatio
        let sideScale = OrbitConfig.previewSideScale

        switch relativeIndex(for: index) {
        case 0:
            return (.zero, 1, 1, 2)
        case -1:
            return (CGSize(width: -sideOffset, height: 20), sideScale, 0.8, 1)
        case 1:
            return (CGSize(width: sideOffset, height: 20), sideScale, 0.8, 1)
        default:
            return nil
        }
    }

    private func relativeIndex(for index: Int) -> Int {
        let count = model.previews.count
        guard count > 0 else { return 0 }

        let raw = index - selectedIndex
        if raw > count / 2 {
            return raw - count
        }
        if raw < -(count / 2) {
            return raw + count
        }
        return raw
    }

    private func statusCard(
        systemName: String? = nil,
        app: AppRecord? = nil,
        titleKey: String,
        messageKey: String,
        hintKey: String? = nil,
        actionKey: String? = nil,
        action: (() -> Void)? = nil,
        showsProgress: Bool = false
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OrbitPalette.burgundy.opacity(0.11))
                    .frame(width: 74, height: 74)

                if let app {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(OrbitPalette.burgundy)
                }
            }

            VStack(spacing: 5) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(LocalizedStringKey(messageKey))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let hintKey {
                    Text(LocalizedStringKey(hintKey))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrbitPalette.burgundy)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(OrbitPalette.burgundy)
            }

            if let actionKey, let action {
                Text(LocalizedStringKey(actionKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitPalette.burgundy)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(OrbitPalette.burgundy.opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
            }
        }
        // Wide enough to carry roughly the disc's visual weight on its own half
        // — at 360 the empty state was noticeably lighter than the ring facing
        // it — while still keeping the message to a couple of short lines.
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }
}

/// One window in the carousel. The stage it is handed is the same shape for
/// every window, but the border has to hug the picture — which is a different
/// shape in each. So the artwork floats inside the stage at its own ratio and
/// carries the fill, clip, border and shadow with it. The opaque fill is what
/// keeps a translucent capture readable over the desktop behind it.
private struct OrbitPreviewWindowCard: View {
    let preview: WindowPreview
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        Color.clear
            .overlay {
                artwork
                    .aspectRatio(max(preview.aspectRatio, 0.5), contentMode: .fit)
                    .background(OrbitPalette.ivory)
                    .clipShape(shape)
                    .overlay(
                        shape.stroke(
                            isSelected ? OrbitPalette.burgundy : .black.opacity(0.08),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    )
                    .shadow(
                        color: .black.opacity(isSelected ? 0.24 : 0.14),
                        radius: isSelected ? 18 : 10,
                        y: isSelected ? 8 : 4
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(preview.title))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = preview.image {
            // Frames are captured in device pixels, so declare that scale
            // rather than letting SwiftUI read them as points and resample.
            Image(decorative: image, scale: preview.scale)
                .resizable()
                .interpolation(.high)
                .opacity(preview.isStale ? 0.75 : 1)
        } else {
            // Nothing capturable and nothing cached — the title is still
            // enough to pick the right window by.
            Color.clear
                .overlay(
                    Text(preview.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(16)
                )
        }
    }
}

private struct OrbitAppCard: View {
    let app: AppRecord
    let cardNumber: Int
    /// Where the card sits on the ring, in radians (0 = 3 o'clock).
    let angle: Double
    let isSelected: Bool
    let isDragging: Bool
    let isVanishing: Bool
    let dragOffset: CGSize
    let onSelect: () -> Void
    let onHoverSelect: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var scatterProgress = 0.0

    /// Rotating by the ring angle plus a quarter turn points the card's
    /// bottom edge — the shortcut hint — at the center, so the icon always
    /// faces outward.
    private var cardRotation: Angle {
        .radians(angle + .pi / 2)
    }

    private var shortcutHint: String {
        var hints: [String] = []
        if OrbitConfig.numericShortcutsEnabled, cardNumber <= 9 {
            hints.append(String(cardNumber))
        }
        if OrbitConfig.letterShortcutsEnabled, let letter = app.letterShortcut {
            hints.append(String(letter).lowercased())
        }
        return hints.joined(separator: " · ")
    }

    var body: some View {
        let size = OrbitConfig.cardSize
        let dimension = size.dimension
        let cornerRadius = dimension * 0.17

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.iconDimension, height: size.iconDimension)

            Spacer(minLength: 0)

            if !shortcutHint.isEmpty {
                Text(shortcutHint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(hintColor)
                    .lineLimit(1)
            }
        }
        .padding(.top, dimension * 0.16)
        .padding(.bottom, dimension * 0.1)
        .frame(width: dimension, height: size.height)
        .background(cardBackground(cornerRadius: cornerRadius))
        // Selection reads through lift and shadow, the way the reference does;
        // the accent hairline is only there to stay legible without color.
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? OrbitPalette.burgundy.opacity(0.9) : borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(
            color: isDragging ? OrbitPalette.burgundy.opacity(0.24) : .black.opacity(isSelected ? 0.20 : 0.10),
            radius: isSelected ? 24 : 16,
            y: isSelected ? 10 : 4
        )
        .scaleEffect(isSelected ? 1.1 : 1)
        .rotationEffect(cardRotation)
        .offset(dragOffset)
        .opacity(isVanishing ? 0.35 : 1)
        // Particles are drawn in unrotated screen space, so aim them straight
        // at the ring center rather than at the card's own bottom edge.
        .cardScatter(progress: scatterProgress, towards: angle + .pi)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in onDragChanged(value.translation) }
                .onEnded { _ in onDragEnded() }
        )
        .onHover { isHovering in
            if isHovering && !isDragging {
                onHoverSelect()
            }
        }
        .onChange(of: isVanishing) { _, newValue in
            if newValue {
                withAnimation(.easeIn(duration: OrbitConfig.dispersionDuration)) {
                    scatterProgress = 1
                }
            } else {
                scatterProgress = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(app.name))
        .accessibilityHint(Text(isSelected ? "accessibility.selected" : "accessibility.select"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let material: AnyShapeStyle
        switch OrbitConfig.cardMaterial {
        case .white:
            material = AnyShapeStyle(isDragging ? OrbitPalette.ivory : Color.white)
        case .black:
            material = AnyShapeStyle(Color.black.opacity(0.86))
        case .system:
            material = AnyShapeStyle(.regularMaterial)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(material)
    }

    private var hintColor: Color {
        switch OrbitConfig.cardMaterial {
        case .white: .black.opacity(0.42)
        case .black: .white.opacity(0.55)
        case .system: .secondary
        }
    }

    private var borderColor: Color {
        switch OrbitConfig.cardMaterial {
        case .white: .black.opacity(0.06)
        case .black: .white.opacity(0.12)
        case .system: .white.opacity(0.2)
        }
    }
}

private struct OrbitCenterControl: View {
    let mode: OrbitCenterMode
    @Binding var isFileTargeted: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    /// Keep the hub visible so a file drag has an obvious destination. The
    /// state label changes from Cancel/confirm to Share/Trash as the drag
    /// enters and stays over the target.
    private var isVisible: Bool {
        true
    }

    var body: some View {
        ZStack {
            // The forgiving hit target extends beyond the visible hub so a
            // Finder drag does not require pixel-perfect aim.
            Color.clear
                .frame(
                    width: OrbitConfig.centerDropRadius * 2,
                    height: OrbitConfig.centerDropRadius * 2
                )
                .contentShape(Circle())

            if isVisible {
                // 圆点和胶囊之间留够距离，否则整个中心读成一根棒棒糖。
                VStack(spacing: 10) {
                    ZStack {
                        hub
                            .frame(
                                width: OrbitConfig.centerRadius * 2,
                                height: OrbitConfig.centerRadius * 2
                            )

                        Image(systemName: centerIcon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text(centerLabel)
                        .font(.system(size: 12, weight: .medium))
                        // 默认状态不该跟卡片抢视线，进入某个动作之后才回到主色。
                        .foregroundStyle(mode == .cancel ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        // 点中心 = 中心当时说它会做的那件事。
        //
        // Switched on the mode rather than filtered by a list of modes it is
        // not: `.confirm` used to fall through to the cancel branch, so a hub
        // painted burgundy, wearing an arrow and captioned "release to switch"
        // dismissed the ring instead. The drag-owned modes still do nothing —
        // the drag's own gestures decide what happens when it is let go.
        .onTapGesture {
            switch mode {
            case .cancel: onCancel()
            case .confirm: onConfirm()
            case .quit, .cleanup, .trash, .share, .failed: break
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isFileTargeted, perform: onDrop)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(centerLabel))
    }

    private var centerIcon: String { mode.iconName }

    private var centerLabel: String {
        switch mode {
        case .cancel: NSLocalizedString("center.cancel", comment: "")
        case .confirm: NSLocalizedString("center.confirm", comment: "")
        case .quit: NSLocalizedString("center.quit", comment: "")
        case .cleanup: NSLocalizedString("center.cleanup", comment: "")
        case .share: NSLocalizedString("center.share", comment: "")
        case .trash: NSLocalizedString("center.trash", comment: "")
        case .failed: NSLocalizedString("center.failed", comment: "")
        }
    }

    /// 中心是一颗石墨磨砂玻璃，不是一块纯色塑料按钮。
    ///
    /// 每个状态都共用同一层底，颜色只作为染层叠在上面。Painting each state its
    /// own solid colour is what made the hub jump between near-black, burgundy
    /// and ivory as a drag crossed it, and it is why Cancel — a state that means
    /// nothing is happening — was the loudest thing on screen. One base means
    /// the states differ by a hue rather than by a step in brightness, and it
    /// keeps the hub on the same material as the track and the preview.
    ///
    /// The tints also have to stay dark enough for a white glyph: `coral` and
    /// `denim` are pale on their own, and the two states that wear them —
    /// quitting an app, throwing files away — are the two that can least afford
    /// an icon that is hard to read.
    private var hub: some View {
        ZStack {
            // 一层平铺的黑只会把它压成一颗失效的灰按钮。让暗部有方向，它才是玻璃。
            // Lit from the same top-left as the cards and the track.
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle().fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.38),
                                .black.opacity(0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            Circle().fill(centerTint)
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1))
        // 只有真的能按下去的状态才发光，默认状态安静。光圈要贴着圆点，
        // 再往外一点就变成第二个泡泡了。
        .overlay {
            if let glow = centerGlow {
                Circle()
                    .stroke(glow.opacity(glowOpacity), lineWidth: 4)
                    .scaleEffect(1.08)
            }
        }
        .shadow(
            color: centerGlow?.opacity(0.26) ?? .black.opacity(0.18),
            radius: centerGlow == nil ? 10 : 12,
            y: centerGlow == nil ? 4 : 5
        )
    }

    private var centerTint: Color {
        switch mode {
        case .cancel: .clear
        case .confirm: OrbitPalette.burgundy.opacity(0.62)
        case .quit, .trash, .failed: OrbitPalette.coral.opacity(0.50)
        case .cleanup: OrbitPalette.burgundy.opacity(0.40)
        case .share: OrbitPalette.denim.opacity(0.46)
        }
    }

    /// `nil` 表示这个状态不发光。
    private var centerGlow: Color? {
        switch mode {
        case .cancel: nil
        case .confirm, .cleanup: OrbitPalette.burgundy
        case .quit, .trash, .failed: OrbitPalette.coral
        case .share: OrbitPalette.denim
        }
    }

    /// 退出 App 和丢进废纸篓是唯一两个不可撤销的状态，光圈允许比别人亮一点。
    private var glowOpacity: Double {
        switch mode {
        case .quit, .trash, .failed: 0.20
        default: 0.16
        }
    }
}
