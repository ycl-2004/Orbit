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

        let sourceApps = OrbitPreferences.showOrbitCard ? apps : apps.filter { !$0.isOrbit }
        let limited = Array(sourceApps.prefix(OrbitPreferences.maxVisibleApps))
        if let orbit = sourceApps.first(where: { $0.isOrbit }), !limited.contains(where: { $0.isOrbit }), !limited.isEmpty {
            self.apps = Array(limited.dropLast()) + [orbit]
        } else {
            self.apps = limited
        }
        self.showsPreview = showsPreview
            ?? OrbitPreferences.windowPreviewEnabled
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

    var ringRadius: CGFloat {
        OrbitPreferences.ringRadius(cardCount: apps.count)
    }

    var canvasSize: CGFloat {
        OrbitPreferences.ringCanvasSize(cardCount: apps.count)
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
        let step = OrbitPreferences.ringStep(cardCount: apps.count)
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
        let maximum = canvasSize + OrbitPreferences.previewPanelMaximumWidth + OrbitPreferences.previewGap * 2
        // A full twelve-card fan makes a disc wider than the ratio leaves room
        // for, and a disc that overruns its half would sit on the carousel.
        // Widen for it rather than crop it — the ratio is there to keep the
        // ring out of the corner, not to decide how big the fan may get.
        let discDemand = (backdropDiameter + OrbitPreferences.previewGap * 2) * 2
        return max(
            canvasSize,
            min(
                max(visibleWidth * OrbitPreferences.layoutWidthRatio, discDemand, previewDemand),
                visibleWidth - OrbitPreferences.screenMargin * 2,
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
        let half = visibleFrame.width * OrbitPreferences.previewSizingRatio / 2
        let usable = half - OrbitPreferences.previewGap * 2
        let base = min(OrbitPreferences.previewCardMaximumWidth, usable / OrbitPreferences.previewCarouselSpan)
        return max(120, base * OrbitPreferences.previewScale)
    }

    /// 放大预览要靠窗口变宽，不然那一半装不下。
    ///
    /// 跟 `discDemand` 同一个套路：版式比例是用来把圆环从屏幕角落里拉回来的，不是
    /// 用来决定东西能有多大。缩小时不反过来收窄窗口 —— 那会让圆环跟着挪位置，
    /// 而改预览大小不该动到环。
    private var previewDemand: CGFloat {
        guard showsPreview else { return 0 }
        let half = desiredPreviewCardWidth * OrbitPreferences.previewCarouselSpan + OrbitPreferences.previewGap * 2
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
        let stageHeight = previewCardWidth / OrbitPreferences.previewStageAspectRatio + 120
        return CGSize(
            width: layoutWidth,
            height: min(max(canvasSize, stageHeight), screenHeight - 60)
        )
    }

    /// Width of the foreground carousel card. Driven by the half of the window
    /// the preview owns — never by the selected window — so that the stage, and
    /// with it the page control, holds still while arrowing through.
    var previewCardWidth: CGFloat {
        let usable = columnWidth - OrbitPreferences.previewGap * 2
        // 想要多大是一回事，那一半真的装得下多少是另一回事：屏幕不够宽时，
        // 窗口涨不到 `previewDemand`，卡片就得让步。
        return max(120, min(desiredPreviewCardWidth, usable / OrbitPreferences.previewCarouselSpan))
    }

    /// Outer diameter of the band the fan sits on, measured from the cards.
    var backdropDiameter: CGFloat {
        OrbitPreferences.ringBackdropRadius(cardCount: apps.count) * 2
    }

    /// 轨道要盖住的那段角度：正好是首尾两张卡片之间，两端各多留一点。
    ///
    /// The track follows the fixed top anchor through the final card. Angles
    /// decrease as MRU order advances, while the backdrop shape expects an
    /// ascending range, so the last card supplies the lower bound.
    var backdropArc: ClosedRange<Double> {
        let span = apps.count > 1
            ? OrbitPreferences.ringStep(cardCount: apps.count) * Double(apps.count - 1)
            : 0
        let padding = OrbitPreferences.ringTrackEndPadding(cardCount: apps.count)
        return (fanStartAngle - span - padding)...(fanStartAngle + padding)
    }

    /// Read once per showing, like `showsPreview`: the glow must not appear or
    /// vanish underneath a fan that is already on screen.
    let showsBackdrop = OrbitPreferences.ringBackdropEnabled

    /// 轨道线的半径。
    var orbitTrailRadius: CGFloat {
        OrbitPreferences.orbitTrailRadius(cardCount: apps.count)
    }

    /// 扇面的重心离画布中心有多远。
    ///
    /// The canvas is a square centred on the hub, but the fan only ever occupies
    /// one side of it — it opens from 12 o'clock down the left — so centring the
    /// *canvas* in its half leaves the cards hugging the far edge and a screen's
    /// worth of empty wallpaper between them and the carousel. Centring what is
    /// actually drawn closes that gap without touching the fan's anchor, which
    /// has to stay at 12 o'clock for spatial memory to work.
    ///
    /// Only part of it is applied (see `fanRecentring`): correcting the whole
    /// way puts the fan dead centre and the hub visibly off to one side, which
    /// trades one lopsided composition for another.
    var fanCentroid: CGSize {
        guard !apps.isEmpty else { return .zero }
        var sumX = 0.0
        var sumY = 0.0
        for index in apps.indices {
            let angle = angle(for: index)
            sumX += cos(angle)
            sumY += sin(angle)
        }
        let count = Double(apps.count)
        return CGSize(
            width: CGFloat(sumX / count) * ringRadius,
            height: CGFloat(sumY / count) * ringRadius
        )
    }

    /// 画布要往回挪多少，才能让扇面（而不是画布）落在这一半的正中间。
    ///
    /// 只横向纠正。The fan's vertical imbalance is a fraction of its horizontal
    /// one, and correcting it moved the hub off the line the carousel sits on —
    /// buying a few points of balance inside the left column at the cost of the
    /// one alignment that ties the two columns together. The hub and the preview
    /// now share the panel's centre line exactly.
    var fanRecentring: CGSize {
        CGSize(width: -fanCentroid.width * 0.7, height: 0)
    }

    /// 星芯落在面板里的哪一点，用 SwiftUI 的坐标（原点在左上）。
    ///
    /// The scrim is a second window covering the whole screen and has to know
    /// exactly where the hub ends up, which is not the ring column's centre —
    /// `fanRecentring` has already moved it.
    var hubCenterInPanel: CGPoint {
        let size = panelSize
        let column = showsPreview ? columnWidth : size.width
        return CGPoint(
            x: column / 2 + fanRecentring.width,
            y: size.height / 2 + fanRecentring.height
        )
    }

    /// 面板里真正画了东西的两块地方：环和预览各自一块。
    ///
    /// 不能把它们 union 成一个矩形再交给 scrim。The gap between the two
    /// columns is deliberately empty, and a single ellipse around that union
    /// turns the empty desktop into the brightest part of the summon layer.
    /// Keeping the bounds separate lets the backdrop support each object while
    /// leaving the space between them available for the user's eyes and files.
    var contentBounds: [CGRect] {
        let size = panelSize
        let hub = hubCenterInPanel
        let fanReach = OrbitPreferences.ringBackdropRadius(cardCount: apps.count)
            + OrbitPreferences.cardScale.height * 0.5
        let fanBounds = CGRect(
            x: hub.x - fanReach,
            y: hub.y - fanReach,
            width: fanReach * 2,
            height: fanReach * 2
        )
        var bounds = [fanBounds]

        if showsPreview {
            let stage = CGSize(
                width: previewCardWidth * OrbitPreferences.previewCarouselSpan,
                height: previewCardWidth / OrbitPreferences.previewStageAspectRatio + 80
            )
            bounds.append(
                CGRect(
                    x: columnWidth * 1.5 - stage.width / 2,
                    y: size.height / 2 - stage.height / 2,
                    width: stage.width,
                    height: stage.height
                )
            )
        }

        return bounds
    }

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

    /// 把一份结果摆上面板，中途的和最终的走同一条路。
    ///
    /// 第一份中间结果一到就切出 `.loading`：面板已经有图可看了，还挂着转圈只是
    /// 让人多等一拍。真正空手而归的情况由 `loadPreviews` 收尾时处理。
    private func publish(_ captured: [WindowPreview]) {
        previews = Array(captured.prefix(OrbitPreferences.maxVisiblePreviews))
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
        return Self.windowTargetWithoutCapture(
            for: selectedApp,
            currentWindow: currentWindow,
            preferredCurrentAppWindow: preferredCurrentAppWindow,
            recentWindowIDs: AppActivationHistory.shared.recentWindowIDs(for: selectedApp.id)
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
    /// `nonisolated` 且参数全部传入，纯粹是为了能被单测直接调用。
    nonisolated static func windowTargetWithoutCapture(
        for app: AppRecord,
        currentWindow: CurrentWindow?,
        preferredCurrentAppWindow: WindowTarget?,
        recentWindowIDs: [CGWindowID],
        lookup: (pid_t, CGWindowID?, [CGWindowID]) -> WindowTarget? = {
            WindowServerInspector.mostRecentOtherWindow(
                ownedBy: $0,
                excluding: $1,
                preferredIDs: $2
            )
        }
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
    }

    /// 让卡片沿着来时的路收回中心。调用方负责在动画走完之后撤掉窗口。
    func beginCollapse() {
        isCollapsing = true
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
            selectedID = entryCardID
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
                let remaining = max(0, OrbitPreferences.dispersionDuration - OrbitPreferences.quitGracePeriod)
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
        let remaining = max(0, OrbitPreferences.dispersionDuration - OrbitPreferences.quitGracePeriod)
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
            if self.dismissAfterFileDrop {
                self.dismissAfterFileDrop = false
                self.onCancel?()
            }
        }
        dragExitTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitPreferences.fileDragExitGrace, execute: task)
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

    @Environment(\.colorScheme) private var colorScheme

    @State private var hasAppeared = false

    var body: some View {
        layout
            .frame(width: model.panelSize.width, height: model.panelSize.height)
            .onAppear { hasAppeared = true }
    }

    /// 1 表示扇面已经完全展开，0 表示所有卡片都还叠在中心。
    ///
    /// The whole panel used to arrive as one 0.9→1 scale, which is the motion a
    /// dialog makes: it says "a thing appeared", not "these came from
    /// somewhere". Deploying each card outward from the hub instead makes the
    /// ring's own geometry the animation — the cards travel the radius they
    /// live on — and gives the dismissal a path to mirror.
    private var deployProgress: Double {
        (hasAppeared && !model.isCollapsing) ? 1 : 0
    }

    /// 每张卡片错开一点起飞，扇面就是"甩"开的而不是"张"开的。
    ///
    /// Only on the way out. Staggering the collapse as well would leave the last
    /// card still travelling after the window is due to go, and a cancel has to
    /// feel immediate.
    private func deployDelay(for index: Int) -> Double {
        model.isCollapsing ? 0 : Double(index) * 0.028
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
                    .opacity(deployProgress)
                    .animation(
                        .easeOut(duration: 0.2).delay(model.isCollapsing ? 0 : 0.06),
                        value: deployProgress
                    )
            }
        } else {
            ringCanvas
        }
    }

    private var ringCanvas: some View {
        let hub = CGPoint(x: model.canvasSize / 2, y: model.canvasSize / 2)

        return ZStack {
            if model.showsBackdrop {
                OrbitRingBackdrop(
                    radius: model.ringRadius,
                    thickness: OrbitPreferences.ringTrackThickness,
                    arc: model.backdropArc,
                    tint: OrbitPalette.backdropOnDusk
                )
                .position(hub)
                .opacity(deployProgress)
                .animation(.easeOut(duration: 0.28), value: deployProgress)
                .zIndex(-2)
            }

            // 虚线是笔，不是气氛，所以它跟 accent 走 —— Welcome 那条轨道用的
            // 也是 accent。跟着 backdrop 开关一起收：把柔光关掉的人要的是光秃
            // 的扇面，不是换一件新装饰。
            //
            // 用 `accentOnDusk` 而不是 `accent(on:)`：这根线落在 scrim 上，而
            // scrim 两个主题下都是暖影，所以决定它多亮的是那块地，不是系统主题。
            if model.showsBackdrop {
                OrbitTrail(
                    radius: model.orbitTrailRadius,
                    arc: model.backdropArc,
                    stops: model.apps.indices.map { model.angle(for: $0) },
                    selectedStop: model.selectedIndex,
                    tint: OrbitPalette.accentOnDusk,
                    progress: deployProgress
                )
                .position(hub)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: deployProgress)
                .zIndex(-1)
            }

            ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                let basePosition = model.position(for: index)
                OrbitAppCard(
                    app: app,
                    cardNumber: index + 1,
                    depthIndex: index,
                    depthCount: model.apps.count,
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
                        let distance = hypot(draggedCenter.x - hub.x, draggedCenter.y - hub.y)
                        model.updateAppDrag(
                            app,
                            offset: offset,
                            overCenter: distance <= OrbitPreferences.centerRadius + 28
                        )
                    },
                    onDragEnded: { model.finishAppDrag(app) }
                )
                // 卡片是从中心甩出去的，收的时候原路收回去。
                .position(deployed(basePosition, from: hub))
                .scaleEffect(0.55 + 0.45 * deployProgress)
                .opacity(deployProgress)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.8)
                        .delay(deployDelay(for: index)),
                    value: deployProgress
                )
                // A lifted card must never slide underneath its neighbours.
                .zIndex(model.draggedAppID == app.id ? 2 : (model.selectedID == app.id ? 1 : 0))
            }

            OrbitCenterControl(
                mode: model.centerMode,
                selectionToken: model.selectedID,
                isFileTargeted: Binding(
                    get: { model.fileDropPhase.acceptsHover },
                    set: { model.setFileDragTargeted($0) }
                ),
                onCancel: { model.cancel() },
                onConfirm: { model.confirmFromHub() },
                onDrop: { providers in model.handleFileDrop(providers) }
            )
            .position(hub)
            // 星芯先亮起来，卡片才从它里面飞出去 —— 光源不能比被照亮的东西晚到。
            .scaleEffect(0.7 + 0.3 * deployProgress)
            .opacity(deployProgress)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: deployProgress)
            .zIndex(3)
        }
        .frame(width: model.canvasSize, height: model.canvasSize)
        .background(Color.clear)
        // 画布按扇面的重心回正，而不是按它自己的几何中心。
        .offset(model.fanRecentring)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.selectedID)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.centerMode)
    }

    /// 卡片在展开途中该待的位置：从中心一路走到它在环上的家。
    private func deployed(_ destination: CGPoint, from hub: CGPoint) -> CGPoint {
        let t = CGFloat(deployProgress)
        return CGPoint(
            x: hub.x + (destination.x - hub.x) * t,
            y: hub.y + (destination.y - hub.y) * t
        )
    }
}

/// A compact carousel of every window belonging to the selected app. The
/// selected window stays in front while its neighbours peek out on either
/// side, matching the way a person scans a small stack of related screens.
private struct OrbitPreviewPanel: View {
    @ObservedObject var model: OrbitRingViewModel

    @Environment(\.colorScheme) private var colorScheme

    private var selectedIndex: Int {
        guard model.previews.indices.contains(model.selectedWindowIndex) else { return 0 }
        return model.selectedWindowIndex
    }

    private var cardScale: CGSize {
        let width = model.previewCardWidth
        return CGSize(
            width: width,
            height: (width / OrbitPreferences.previewStageAspectRatio).rounded()
        )
    }

    var body: some View {
        Group {
            switch model.previewState {
            // 空态和加载态不给容器。
            //
            // A panel the size of a real preview, holding one icon and two
            // lines, was the largest and emptiest object on the screen — it
            // announced that something was missing rather than quietly waiting
            // for a selection. Dropping the glass keeps the column's width
            // reserved, so nothing jumps when a preview does arrive, while the
            // half itself goes back to being empty space.
            case .idle:
                statusCard(
                    systemName: "square.grid.2x2",
                    titleKey: "preview.empty.title",
                    messageKey: "preview.empty.message",
                    chromeless: true,
                    horizontalOffset: -24
                )
            case .loading:
                statusCard(
                    systemName: "rectangle.inset.filled",
                    titleKey: "preview.loading.title",
                    messageKey: "preview.loading.message",
                    showsProgress: true,
                    chromeless: true
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
        // 翻页器贴到卡片下面来。
        //
        // At 16 with a stage that reserved another 24 of slack, the control sat
        // far enough below the deck to read as a separate object floating on the
        // desktop rather than as this carousel's own pager. Proximity is the
        // whole of the relationship here.
        VStack(spacing: 10) {
            ZStack {
                ForEach(Array(model.previews.enumerated()), id: \.element.id) { index, preview in
                    if let position = deckPosition(for: index) {
                        OrbitPreviewWindowCard(
                            preview: preview,
                            isSelected: index == selectedIndex
                        )
                        .frame(width: cardScale.width, height: cardScale.height)
                        .scaleEffect(position.scale)
                        .offset(position.offset)
                        .opacity(position.opacity)
                        .zIndex(position.zIndex)
                        .transition(.opacity)
                        .onTapGesture { model.selectedWindowIndex = index }
                    }
                }
            }
            .frame(height: cardScale.height + 12)

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
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
        let sideOffset = cardScale.width * OrbitPreferences.previewSideOffsetRatio
        let sideScale = OrbitPreferences.previewSideScale

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
        showsProgress: Bool = false,
        chromeless: Bool = false,
        horizontalOffset: CGFloat = 0
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                // 空态连这圈底也不要：一个没有内容的图标不该先给自己盖一个座。
                if !chromeless {
                    Circle()
                        .fill(OrbitPalette.burgundy.opacity(0.11))
                        .frame(width: 74, height: 74)
                }

                if let app {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: chromeless ? 22 : 27, weight: .medium))
                        .foregroundStyle(OrbitPalette.accent(on: colorScheme).opacity(chromeless ? 0.75 : 1))
                }
            }
            .frame(height: chromeless ? 30 : 74)

            VStack(spacing: 5) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // 半透明底上的正文加一档字重 —— 玻璃后面的浅灰细体是这套材质
                // 里最先糊掉的东西。
                Text(LocalizedStringKey(messageKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let hintKey {
                    Text(LocalizedStringKey(hintKey))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrbitPalette.accent(on: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(OrbitPalette.accent(on: colorScheme))
            }

            if let actionKey, let action {
                Text(LocalizedStringKey(actionKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitPalette.accent(on: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(OrbitPalette.accent(on: colorScheme).opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
            }
        }
        // Wide enough to keep the message to a couple of short lines.
        .frame(maxWidth: 420)
        .padding(.horizontal, chromeless ? 18 : 28)
        .padding(.vertical, chromeless ? 12 : 24)
        .modifier(OrbitSurface(enabled: !chromeless))
        .modifier(OrbitTextHalo(enabled: chromeless))
        .offset(x: horizontalOffset)
    }
}

/// 无容器状态背后那团看不出边的底。
///
/// 上一版把空态的玻璃盒去掉是对的，但去得太干净了：文字直接落在桌面上，正好压在
/// 一排文件夹图标之间，读不了。The fix is not to put the box back — an empty
/// state should not occupy the same volume as a full one — it is to give the
/// text a ground the size of the text. A heavily blurred plate in the window's
/// own background colour has no edge anyone can see, costs nothing in perceived
/// weight, and survives any wallpaper underneath it.
private struct OrbitTextHalo: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // 这块底大部分时候是叠在那潭柔光上的 —— contentBounds 已经把预览这
            // 一列圈进去了 —— 所以它只需要兜住潭够不到的那一点边缘。
            //
            // 但潭的底换成暖影之后，这层从"别再加亮了"变成了整段文字唯一的依
            // 靠：the status text is `.primary`, which in the light theme is ink
            // on a ground that is no longer pale. 提到 0.34 是让它重新变回一小
            // 块纸 —— 环上其它每样东西都有自己的底，这段字凭什么没有。
            content.background {
                Ellipse()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .opacity(0.34)
                    .blur(radius: 24)
                    .padding(-18)
            }
        } else {
            content
        }
    }
}

/// 预览那一侧的面，跟 Welcome 的卡片同一种做法。
///
/// `.regularMaterial` + `.white.opacity(0.7)` 的边 + 一层很轻的黑影 —— 这三样
/// 是 onboarding 那一页每一块浮起来的东西都在用的配方。The panel used to have a
/// heavier, differently-lit rim than anything else Orbit draws, which is part of
/// why the two halves of the window never read as one object. Sharing the recipe
/// is cheaper than inventing a second one and it is what makes them match.
private struct OrbitSurface: ViewModifier {
    let enabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 开了「增强对比度」就把边收实。
    ///
    /// The setting exists for people for whom a 1px hairline at 70% white is not
    /// an edge. Meeting it with a defined border is the documented answer, and it
    /// costs nothing for everyone else because it is off by default.
    private var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    func body(content: Content) -> some View {
        if enabled {
            let shape = RoundedRectangle(cornerRadius: OrbitRadius.surface, style: .continuous)
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(rim, lineWidth: increasesContrast ? 1.5 : 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 18, y: 8)
        } else {
            content
        }
    }

    /// 暗底上 70% 的白边会亮成一根管子；亮底上它才是"光打在玻璃上沿"。
    private var rim: Color {
        if increasesContrast { return .primary.opacity(0.55) }
        return colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.7)
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
        let shape = RoundedRectangle(cornerRadius: OrbitRadius.tile, style: .continuous)

        Color.clear
            .overlay {
                artwork
                    .aspectRatio(max(preview.aspectRatio, 0.5), contentMode: .fit)
                    .background(OrbitPalette.ivory)
                    .clipShape(shape)
                    // 标题条压在图上，是这张缩略图和它拍的那扇真窗口之间最明确的
                    // 一处不同。
                    //
                    // A capture of a window, shown at a fraction of its size over
                    // a blurred desktop, looks exactly like the window it came
                    // from — in the last build the Terminal preview and the real
                    // Terminal behind it were indistinguishable. A chip Orbit
                    // drew, in Orbit's own material, is the frame that says this
                    // is a picture of a thing rather than the thing.
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            titleChip
                        }
                    }
                    .overlay(
                        shape.stroke(
                            isSelected
                                ? OrbitPalette.burgundy
                                : OrbitPalette.burgundy.opacity(0.22),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    )
                    // 选中的那一张也接住中心的光，跟环上被选中的卡片是同一句话。
                    .shadow(color: .black.opacity(isSelected ? 0.14 : 0.10), radius: 4, y: 2)
                    .shadow(
                        color: isSelected ? OrbitPalette.burgundy.opacity(0.26) : .black.opacity(0.13),
                        radius: isSelected ? 20 : 12,
                        y: isSelected ? 9 : 5
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(preview.title))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var titleChip: some View {
        Text(preview.title)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .padding(.bottom, 10)
            .padding(.horizontal, 12)
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
    /// Render order is also the deck order: later cards sit in front of earlier
    /// cards, so the depth ramp follows the existing spread instead of changing
    /// which card wins an overlap.
    let depthIndex: Int
    let depthCount: Int
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

    @Environment(\.colorScheme) private var colorScheme

    @State private var scatterProgress = 0.0

    private var isDark: Bool { colorScheme == .dark }

    /// Three quiet tiers are enough for the eye to read the fan as a deck.
    /// Selected and dragged states intentionally override these values below.
    private var depthTier: Int {
        guard depthCount > 1 else { return 2 }
        let progress = Double(depthIndex) / Double(depthCount - 1)
        switch progress {
        case ..<0.34: return 0
        case ..<0.67: return 1
        default: return 2
        }
    }

    private var depthOpacity: Double {
        switch depthTier {
        case 0: 0.94
        case 1: 0.97
        default: 1
        }
    }

    private var depthScale: CGFloat {
        switch depthTier {
        case 0: 0.97
        case 1: 0.985
        default: 1
        }
    }

    private var depthContactShadowOpacity: Double {
        switch depthTier {
        case 0: 0.06
        case 1: 0.08
        default: 0.10
        }
    }

    private var depthAmbientShadowOpacity: Double {
        switch depthTier {
        case 0: 0.07
        case 1: 0.10
        default: 0.13
        }
    }

    private var depthAmbientShadowRadius: CGFloat {
        switch depthTier {
        case 0: 12
        case 1: 14
        default: 16
        }
    }

    private var depthAmbientShadowY: CGFloat {
        switch depthTier {
        case 0: 5
        case 1: 6
        default: 8
        }
    }

    /// 卡片只跟着扇面转一部分，不是转满。
    ///
    /// `angle + .pi / 2` is the full turn that would point every card's bottom
    /// edge at the hub. Taking a fraction of it keeps the spread readable while
    /// leaving each card near enough upright that the fan has a baseline — see
    /// `OrbitPreferences.cardRotationFollow` for why a fully-followed fan reads
    /// as dropped rather than dealt.
    private var cardRotation: Angle {
        .radians(rotationRadians)
    }

    private var rotationRadians: Double {
        (angle + .pi / 2) * OrbitPreferences.cardRotationFollow
    }

    /// 中心在卡片自己坐标系里的方向。
    ///
    /// The hub sits at `angle + .pi` from the card in screen space; the card is
    /// then rotated, so what the card itself has to be lit from is that
    /// direction minus its own rotation. Working it out rather than fixing the
    /// light to the bottom edge is what lets the highlight stay pointed at the
    /// hub at any `cardRotationFollow`, including zero.
    private var hubDirection: Double {
        angle + .pi - rotationRadians
    }

    /// 靠中心的那条边，在 `UnitPoint` 里的位置。
    private var hubSide: UnitPoint {
        UnitPoint(x: 0.5 + 0.5 * cos(hubDirection), y: 0.5 + 0.5 * sin(hubDirection))
    }

    private var farSide: UnitPoint {
        UnitPoint(x: 0.5 - 0.5 * cos(hubDirection), y: 0.5 - 0.5 * sin(hubDirection))
    }

    /// 选中的卡片被中心拉近一点 —— 屏幕坐标，所以不跟着卡片一起转。
    private var gravityOffset: CGSize {
        guard isSelected, !isDragging else { return .zero }
        let pull = OrbitPreferences.selectionGravityPull
        return CGSize(width: cos(angle + .pi) * pull, height: sin(angle + .pi) * pull)
    }

    private var shortcutHint: String {
        var hints: [String] = []
        if OrbitPreferences.numericShortcutsEnabled, cardNumber <= 9 {
            hints.append(String(cardNumber))
        }
        if OrbitPreferences.letterShortcutsEnabled, let letter = app.letterShortcut {
            hints.append(String(letter).lowercased())
        }
        return hints.joined(separator: " · ")
    }

    /// 卡片底下那行字：平时是快捷键，选中之后换成应用名。
    ///
    /// 换而不是加：the shortcut is what you needed while you were still looking
    /// for this card, and it is the one thing you no longer need once you have
    /// found it. Swapping keeps the card the same height and the fan the same
    /// shape, so confirming what is selected costs no layout at all.
    private var caption: String? {
        if isSelected {
            return app.name
        }
        return shortcutHint.isEmpty ? nil : shortcutHint
    }

    var body: some View {
        let size = OrbitPreferences.cardScale
        let dimension = size.dimension
        let cornerRadius = OrbitRadius.card(dimension)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.iconDimension, height: size.iconDimension)

            Spacer(minLength: 0)

            if let caption {
                Text(caption)
                    .font(.system(size: isSelected ? 11 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? OrbitPalette.accent(on: colorScheme) : hintColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: dimension - 12)
            }
        }
        .padding(.top, dimension * 0.16)
        .padding(.bottom, dimension * 0.1)
        .frame(width: dimension, height: size.height)
        .background(cardBackground(cornerRadius: cornerRadius))
        // 光是从中心来的：靠中心那一侧亮，远端沉下去。这是整个环里唯一一处
        // 说明「哪儿有光源」的地方，也是卡片不再像贴纸的原因。
        .overlay {
            LinearGradient(
                colors: [
                    OrbitPalette.starCore.opacity(lightStrength),
                    .clear
                ],
                startPoint: hubSide,
                endPoint: farSide
            )
            .clipShape(shape)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        // Selection reads through lift, scale and the pull toward the hub; the
        // rim is here so it stays legible without relying on colour alone.
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: rimColors,
                    startPoint: hubSide,
                    endPoint: farSide
                ),
                lineWidth: isSelected ? 1.5 : 1
            )
        )
        // 两层投影：一层贴身的接触影给重量，一层散开的环境影给高度。
        //
        // 一层做不到。A single soft shadow that is dark enough to weigh the card
        // down turns into a bruise, and one light enough to stay clean leaves a
        // white card floating on the pale ground with nothing holding it — which
        // is exactly what the last pass shipped. Splitting the job is how real
        // shadows work and it is the cheapest way to get both.
        // 暗底上投影是白费的 —— 黑影落在暗地上什么也看不出来，还会把叠着的
        // 卡片之间糊得更平。那一档的分离交给边框。
        .shadow(color: isDark ? .clear : contactShadow, radius: isSelected ? 4 : 3, y: 2)
        .shadow(
            color: isDragging ? OrbitPalette.burgundy.opacity(0.24) : .black.opacity(isSelected ? 0.16 : depthAmbientShadowOpacity),
            radius: isSelected ? 22 : depthAmbientShadowRadius,
            y: isSelected ? 11 : depthAmbientShadowY
        )
        .scaleEffect(isSelected ? 1.1 : depthScale)
        .rotationEffect(cardRotation)
        .offset(gravityOffset)
        .offset(dragOffset)
        .opacity(isVanishing ? 0.35 : (isSelected || isDragging ? 1 : depthOpacity))
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
                withAnimation(.easeIn(duration: OrbitPreferences.dispersionDuration)) {
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
        switch OrbitPreferences.cardFinish {
        case .white:
            // 拖起来的那张变象牙，是原本就有的手感提示；静止那张也从纯白退到
            // 近白。
            //
            // 纯白是没有余地的颜色。With the wash behind it pulled down, a card
            // at 1.0 becomes the brightest thing on the screen by a margin and
            // the fan reads as a row of light boxes rather than as paper. Half a
            // step down still reads as a white card and leaves the hub — the one
            // thing that is supposed to be emitting — somewhere to be brighter
            // than.
            material = AnyShapeStyle(isDragging ? OrbitPalette.ivory : OrbitPalette.paper)
        case .black:
            material = AnyShapeStyle(Color.black.opacity(0.86))
        case .system:
            material = AnyShapeStyle(.regularMaterial)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(material)
    }

    private var hintColor: Color {
        switch OrbitPreferences.cardFinish {
        case .white: .black.opacity(0.42)
        case .black: .white.opacity(0.55)
        case .system: .secondary
        }
    }

    private var borderColor: Color {
        switch OrbitPreferences.cardFinish {
        case .white: .black.opacity(0.06)
        case .black: .white.opacity(0.12)
        case .system: .white.opacity(0.2)
        }
    }

    /// 打在卡片上的光有多强 —— 白卡片本来就亮，再加光只会糊掉。
    ///
    /// 明显比第一版轻。The light source is an ivory bead now, not a burning
    /// core, and a white card lit hard by a pale light just loses its own edge.
    private var lightStrength: Double {
        let base: Double = switch OrbitPreferences.cardFinish {
        // 白面上几乎不加：它已经快到顶了，任何 `plusLighter` 都只是在推高总亮度，
        // 换不来一点形体。The dark finish is where this actually models anything.
        case .white: 0.03
        case .black: 0.24
        case .system: 0.12
        }
        return isSelected ? base * 1.5 : base
    }

    /// 贴着卡片底边那一道接触影。
    private var contactShadow: Color {
        .black.opacity(isSelected ? 0.16 : depthContactShadowOpacity)
    }

    /// 边框也跟着光走：向着中心的那条边接住高光，背光的一边收在主色的发丝线上。
    ///
    /// 未选中那根线用 Welcome 的 0.18。It is the weight the onboarding
    /// illustration outlines everything with, and it is what keeps a white card
    /// on a warm white ground from having to rely on its shadow alone.
    ///
    /// 暗底上换成白线，而且要比浅色那根更实。
    ///
    /// An accent hairline at 0.18 is invisible against a dark ground, so the
    /// shadow side has to swap material rather than just get louder. It also has
    /// to do more work there: **a shadow cast onto a dark ground is not visible
    /// at all**, so on the dark theme the rim is the *only* thing separating one
    /// black card from the black card overlapping it — and the fan's lower arm
    /// is where three or four of them stack. In light the shadow carries that
    /// job and the rim can stay a whisper.
    private var rimColors: [Color] {
        let far: Color = if isSelected {
            OrbitPalette.accent(on: colorScheme).opacity(0.85)
        } else if isDark {
            .white.opacity(0.26)
        } else {
            OrbitPalette.burgundy.opacity(0.18)
        }
        return [.white.opacity(isSelected ? 0.9 : 0.75), far]
    }
}

private struct OrbitCenterControl: View {
    let mode: OrbitCenterMode
    /// 选中项换了没有 —— 只用来触发一次脉冲，中心不关心选的是谁。
    let selectionToken: String?
    @Binding var isFileTargeted: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 每次换选中项，星芯轻轻鼓一下。
    ///
    /// Arrowing from one card to the next changes two things far apart on
    /// screen — the card that grew, and the preview that reloaded — and nothing
    /// at the point the eye actually rests. A beat at the centre ties them
    /// together. It has to be small: this fires on every keypress, and anything
    /// with a visible travel becomes a stutter at speed.
    @State private var pulse = false

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
                    width: OrbitPreferences.centerDropRadius * 2,
                    height: OrbitPreferences.centerDropRadius * 2
                )
                .contentShape(Circle())

            if isVisible {
                // 圆点和胶囊之间留够距离，否则整个中心读成一根棒棒糖。
                VStack(spacing: 10) {
                    ZStack {
                        hub
                            .frame(
                                width: OrbitPreferences.centerRadius * 2,
                                height: OrbitPreferences.centerRadius * 2
                            )
                            .scaleEffect(pulse ? 1.06 : 1)

                        // 默认状态不戴符号，戴一枚轨道标记。
                        //
                        // A × at the centre of the composition told everyone who
                        // summoned the ring that the likeliest thing they wanted
                        // was to give up, so it went — but an empty bead read as
                        // a placeholder waiting to be filled, which is not what
                        // the anchor of the whole layout should be. The mark is
                        // the product's own idea at its smallest: a ring, and
                        // something on it.
                        if let centerIcon {
                            Image(systemName: centerIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(glyphInk)
                        } else {
                            orbitMark
                        }
                    }

                    caption
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
        .onChange(of: selectionToken) { _, _ in
            // 鼓起来用弹簧，落回去慢一点，读起来才是"回弹"而不是"抽搐"。
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pulse = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75).delay(0.09)) { pulse = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(centerLabel))
    }

    /// `nil` 表示这个状态不戴符号。
    private var centerIcon: String? {
        mode == .cancel ? nil : mode.iconName
    }

    /// 空态的中心标记：一圈轨道，上面挂一颗。
    ///
    /// 用形状画而不是拿一个 SF Symbol 凑。The mark has to be the same idea the
    /// dashed arc outside it is drawing, at a twentieth of the size, and no
    /// stock glyph is that. It also stays legible at every card scale because it
    /// is built from the hub's own radius rather than from a font size.
    private var orbitMark: some View {
        let unit = OrbitPreferences.centerRadius
        return ZStack {
            Circle()
                .strokeBorder(OrbitPalette.accent(on: colorScheme).opacity(0.34), lineWidth: 1.2)
                .frame(width: unit * 0.62, height: unit * 0.62)

            Circle()
                .fill(OrbitPalette.accent(on: colorScheme).opacity(0.55))
                .frame(width: unit * 0.16, height: unit * 0.16)
                .offset(y: -unit * 0.31)
        }
    }

    /// 中心下面那行字。
    ///
    /// 默认状态只留一枚键帽。The way out still has to be visible — cutting the
    /// label entirely would trade a hub that shouts "give up" for one that says
    /// nothing about how to leave — but a key cap teaches the keyboard, which is
    /// how the ring is actually driven, instead of advertising the mouse target.
    @ViewBuilder
    private var caption: some View {
        if mode == .cancel {
            // 跟 Welcome 的 `KeycapView` 同一颗键帽：圆角 6，regularMaterial，
            // quaternary 的边。同一个键在两个地方长得一样，才教得会人。
            Text(verbatim: "esc")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        } else {
            Text(centerLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
        }
    }

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

    /// 中心是这个场景里唯一的光源，不是一颗按钮。
    ///
    /// 之前它是一块石墨玻璃：构图的圆心上放着画面里最沉的东西，于是整个环没有
    /// 任何地方能解释卡片的高光是从哪儿来的。A core that actually emits — bright
    /// at the centre, falling through the state's hue to a dark edge, with a
    /// corona around it — gives the ring a light source, and it is what every
    /// lit card edge and every glowing trail on screen is now consistent with.
    ///
    /// 状态之间只换色相，不换亮度层级：每个状态共用同一条从亮到暗的梯度，所以
    /// 拖拽穿过中心时它变的是颜色，不是忽明忽暗地跳。The hues also have to stay
    /// deep enough at the edge for a white glyph — `coral` and `denim` are pale
    /// on their own, and the states wearing them (quitting an app, throwing
    /// files away) are the two that can least afford an icon that is hard to
    /// read.
    private var hub: some View {
        ZStack {
            // 象牙底，跟 Welcome 中心那块白色圆角砖是同一种东西 —— 一颗浅色的
            // 珠子，不是一口深色的井。
            //
            // 暗色调下让它透一点，底下的暗透上来，象牙就沉成暖米色。A full-strength
            // cream disc on a dark ground is the brightest thing by a wide
            // margin and reads as a lamp shining into the room; it should be the
            // light *in* the room.
            Circle().fill(OrbitPalette.ivory.opacity(colorScheme == .dark ? 0.72 : 1))

            // 颜色只作为一层很淡的染色浮在上面，中心留白。States差的是色相和
            // 浓度，不是明暗档位，所以拖拽穿过中心时它变色而不是忽明忽暗。
            //
            // 高光收回中心、压低、摊开。An off-centre specular at near-full
            // strength turned the hub into a glossy egg — a rendered object with
            // a light hitting it, sitting in a layout made of flat paper. What
            // it should read as is Welcome's white tile: a calm disc that
            // happens to be the brightest thing on screen.
            Circle().fill(
                RadialGradient(
                    stops: [
                        .init(color: OrbitPalette.starCore.opacity(colorScheme == .dark ? 0.38 : 0.55), location: 0),
                        .init(color: emission.opacity(tintStrength * 0.5), location: 0.55),
                        .init(color: emission.opacity(tintStrength), location: 1)
                    ],
                    center: .init(x: 0.46, y: 0.43),
                    startRadius: 0,
                    endRadius: OrbitPreferences.centerRadius * 1.3
                )
            )
        }
        // Welcome 用 0.28 的发丝线勾它的中心砖，这里就是同一根线。
        .overlay(Circle().strokeBorder(emission.opacity(0.26), lineWidth: 1))
        // 日冕：贴着珠子的一圈很淡的光，说明光是从这里散出去的。
        .overlay {
            Circle()
                .stroke(emission.opacity(0.10), lineWidth: OrbitPreferences.centerRadius * 0.22)
                .blur(radius: OrbitPreferences.centerRadius * 0.24)
                .scaleEffect(1.14)
                .allowsHitTesting(false)
        }
        // 投影按 Welcome 的分量来：一层浅浅的彩色扩散，一层很轻的黑。
        .shadow(color: emission.opacity(0.14), radius: OrbitPreferences.centerRadius * 0.55, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// 这一状态下星芯染的是什么颜色。
    private var emission: Color {
        switch mode {
        case .cancel, .confirm, .cleanup: OrbitPalette.burgundy
        case .quit, .trash, .failed: OrbitPalette.coral
        case .share: OrbitPalette.denim
        }
    }

    /// 符号的颜色。
    ///
    /// 浅色的珠子配不了白符号。`coral` and `denim` are too pale to be read as ink
    /// on ivory either, so the two states wearing them borrow a deeper relative
    /// of the same hue — the states in question are quitting an app and throwing
    /// files away, the two that can least afford a glyph that is hard to read.
    private var glyphInk: Color {
        switch mode {
        case .cancel, .confirm, .cleanup: OrbitPalette.accent(on: colorScheme)
        case .quit, .trash, .failed: OrbitPalette.ember(0.55)
        case .share: colorScheme == .dark ? OrbitPalette.denim : OrbitPalette.denimInk
        }
    }

    /// 默认状态几乎不上色，真的按得下去的状态才明确染上。
    ///
    /// 暗色下整体再收一档：珠子在暗地上本来就是最亮的东西，酒红染上去会把它推向
    /// 粉，而它该读作暖白。
    private var tintStrength: Double {
        let base = rawTintStrength
        return colorScheme == .dark ? base * 0.78 : base
    }

    private var rawTintStrength: Double {
        switch mode {
        case .cancel: 0.10
        case .cleanup: 0.26
        case .confirm: 0.32
        case .share: 0.34
        case .quit, .trash, .failed: 0.40
        }
    }
}
