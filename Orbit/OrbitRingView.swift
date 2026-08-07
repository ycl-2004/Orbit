//
//  OrbitRingView.swift
//  Orbit
//
//  The ring deliberately separates selection from activation. A card click or
//  hover selects an app; activation happens on Enter or when the trigger key
//  is released. The center is a cancel target unless a card is explicitly
//  dragged into it.
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
    @Published private(set) var apps: [AppInfo]
    @Published var selectedID: String?
    @Published var draggedAppID: String?
    @Published var dragOffset: CGSize = .zero
    @Published var dragOverCenter = false
    @Published var dissolvingAppID: String?
    @Published private(set) var bulkDissolvingAppIDs: Set<String> = []
    @Published var fileDropPhase: FileDropPhase = .idle
    @Published var fileTrashReady = false
    @Published private(set) var previews: [WindowPreview] = []
    @Published private(set) var isLoadingPreviews = false
    @Published private(set) var previewState: OrbitPreviewState = .idle
    /// Which of the selected app's windows the arrow keys point at.
    @Published var selectedWindowIndex = 0

    var onCancel: (() -> Void)?
    /// Second argument is the window title to raise, when one was picked.
    var onActivate: ((AppInfo, String?) -> Void)?

    private var fileTrashTask: DispatchWorkItem?
    private var dragExitTask: DispatchWorkItem?
    /// Cursor position at the moment selection was explicitly cleared.
    private var hoverAnchor: CGPoint?
    /// Where the selection stood when it was cleared, so arrowing again picks
    /// up from there instead of starting over.
    private var resumeIndex: Int?
    private var bulkCleanupPendingIDs: Set<String> = []
    private var bulkCleanupSucceededIDs: Set<String> = []

    /// Captured once per showing: the layout flips and the panel resizes
    /// around this, so it must not change while the ring is on screen.
    let showsPreview: Bool

    init(apps: [AppInfo], showsPreview: Bool? = nil) {
        let sourceApps = OrbitConfig.showOrbitCard ? apps : apps.filter { !$0.isOrbit }
        let limited = Array(sourceApps.prefix(OrbitConfig.maxVisibleApps))
        if let orbit = sourceApps.first(where: { $0.isOrbit }), !limited.contains(where: { $0.isOrbit }), !limited.isEmpty {
            self.apps = Array(limited.dropLast()) + [orbit]
        } else {
            self.apps = limited
        }
        self.showsPreview = showsPreview
            ?? OrbitConfig.windowPreviewEnabled
    }

    var selectedApp: AppInfo? {
        guard let selectedID else { return nil }
        return apps.first(where: { $0.id == selectedID })
    }

    var centerMode: OrbitCenterMode {
        if draggedAppID != nil && dragOverCenter {
            return apps.first(where: { $0.id == draggedAppID })?.isOrbit == true ? .cleanup : .quit
        }
        if fileTrashReady {
            return .trash
        }
        if fileDropPhase.isReceiving {
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

    /// The fan opens symmetrically around one direction, leaving its gap on the
    /// opposite side. Without a preview the gap faces left; with one it faces
    /// right so the cards curl around the preview panel.
    private var fanAxis: Double {
        showsPreview ? .pi : 0
    }

    /// Few apps make a small fan; many apps keep the same step until the fan
    /// hits its 270° limit, then tighten it while the radius grows.
    func angle(for index: Int) -> Double {
        guard apps.count > 1 else { return fanAxis }

        let step = OrbitConfig.ringStep(cardCount: apps.count)
        let span = step * Double(apps.count - 1)
        let offset = step * Double(index)
        // Cards always read top-to-bottom. Mirroring the axis would also
        // mirror that order, so the flipped fan is walked backwards.
        return showsPreview
            ? fanAxis + span / 2 - offset
            : fanAxis - span / 2 + offset
    }

    /// Total size of the panel that hosts the ring, plus the preview when it
    /// is enabled. The preview tucks into the fan's gap rather than sitting
    /// beside an untouched square canvas.
    var panelSize: CGSize {
        guard showsPreview else {
            return CGSize(width: canvasSize, height: canvasSize)
        }
        // A short fan must not squash the carousel: the window grows past the
        // canvas when the ring alone would not give the stage room. The ring
        // stays centered in whatever height that comes to.
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let stageHeight = previewCardWidth / OrbitConfig.previewStageAspectRatio + 120
        return CGSize(
            width: canvasSize + previewPanelWidth - previewOverlap,
            height: min(max(canvasSize, stageHeight), screenHeight - 60)
        )
    }

    /// Sized from what the fan leaves over, so it must be read once and shared
    /// by the window frame and the carousel inside it.
    var previewPanelWidth: CGFloat {
        OrbitConfig.previewPanelWidth(cardCount: apps.count, overlap: previewOverlap)
    }

    /// Width of the foreground carousel card. Driven by the horizontal room
    /// the fan leaves over — never by the selected window — so that the stage,
    /// and with it the page control, holds still while arrowing through.
    var previewCardWidth: CGFloat {
        let byWidth = (previewPanelWidth - previewOverlap - 48) / OrbitConfig.previewCarouselSpan
        return max(160, min(OrbitConfig.previewCardMaximumWidth, byWidth))
    }

    /// How far the preview slides back over the canvas. The fan's end cards
    /// reach `cos(span/2) * radius` past the center, so stop just clear of them.
    var previewOverlap: CGFloat {
        let step = OrbitConfig.ringStep(cardCount: apps.count)
        let halfSpan = step * Double(max(apps.count - 1, 0)) / 2
        let reach = abs(cos(halfSpan)) * ringRadius + OrbitConfig.cardSize.dimension * 0.5
        return max(0, canvasSize / 2 - reach - OrbitConfig.previewGap)
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

    func select(_ app: AppInfo) {
        guard draggedAppID == nil else { return }
        hoverAnchor = nil
        resumeIndex = nil
        selectedID = app.id
    }

    /// Hovering re-selects a card, which would undo an explicit deselect the
    /// moment the card resizes under a stationary cursor. Ignore hover until
    /// the pointer actually moves.
    func selectFromHover(_ app: AppInfo) {
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
            .previews(forProcessIdentifier: app.processIdentifier)
        guard !Task.isCancelled else { return }

        previews = Array(captured.prefix(OrbitConfig.maxVisiblePreviews))
        isLoadingPreviews = false
        if previews.isEmpty {
            if let processesWithWindows = WindowVisibilityChecker.processesWithWindows() {
                previewState = processesWithWindows.contains(app.processIdentifier)
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

    /// Title of the window the arrow keys landed on, if the app has more than
    /// one to choose between.
    var selectedWindowTitle: String? {
        guard previews.indices.contains(selectedWindowIndex) else { return nil }
        return previews[selectedWindowIndex].title
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

        let currentIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) } ?? (step > 0 ? -1 : 0)
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
        guard let match = orderedIndices.first(where: { apps[$0].firstLetter == Character(String(first).uppercased()) }) else {
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

        onActivate?(selectedApp, selectedWindowTitle)
    }

    /// Clears the highlight so releasing the trigger dismisses the ring
    /// instead of switching apps.
    func deselect() {
        guard draggedAppID == nil else { return }
        resumeIndex = selectedID.flatMap { id in apps.firstIndex(where: { $0.id == id }) }
        selectedID = nil
        hoverAnchor = NSEvent.mouseLocation
    }

    func cancel() {
        guard draggedAppID == nil, !fileDropPhase.isReceiving else { return }
        onCancel?()
    }

    func triggerReleased() {
        guard draggedAppID == nil, fileDropPhase == .idle else { return }
        if selectedID == nil {
            onCancel?()
        } else {
            confirmSelection()
        }
    }

    func beginAppDrag(_ app: AppInfo) {
        selectedID = app.id
        draggedAppID = app.id
        dragOffset = .zero
        dragOverCenter = false
    }

    func updateAppDrag(_ app: AppInfo, offset: CGSize, overCenter: Bool) {
        guard draggedAppID == app.id else { return }
        dragOffset = offset
        dragOverCenter = overCenter
    }

    func finishAppDrag(_ app: AppInfo) {
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

        dissolvingAppID = app.id
        app.terminate { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                guard success else {
                    self.dissolvingAppID = nil
                    return
                }

                // 宽限期比消散动画短，所以退出成功之后还要把动画剩下的那一截等完
                // 再抽走卡片 —— 否则碎片飞到一半，卡片就凭空不见了。
                let remaining = max(0, OrbitConfig.dissolveDuration - OrbitConfig.terminateGracePeriod)
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    self.apps.removeAll { $0.id == app.id }
                    self.dissolvingAppID = nil
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
        guard let windowedPIDs = WindowVisibilityChecker.processesWithWindows() else {
            onCancel?()
            return
        }

        let candidates = apps.filter { app in
            !app.isOrbit && !app.isFinder && !windowedPIDs.contains(app.processIdentifier)
        }
        guard !candidates.isEmpty else {
            onCancel?()
            return
        }

        selectedID = nil
        bulkCleanupPendingIDs = Set(candidates.map(\.id))
        bulkCleanupSucceededIDs = []
        bulkDissolvingAppIDs = bulkCleanupPendingIDs

        for app in candidates {
            app.terminate { [weak self] success in
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
        let failed = succeededIDs.count < bulkDissolvingAppIDs.count
        let remaining = max(0, OrbitConfig.dissolveDuration - OrbitConfig.terminateGracePeriod)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self else { return }
            self.apps.removeAll { succeededIDs.contains($0.id) }
            self.bulkDissolvingAppIDs = []
            self.bulkCleanupSucceededIDs = []
            if !failed {
                self.onCancel?()
            }
        }
    }

    func setFileDragTargeted(_ targeted: Bool) {
        if targeted {
            dragExitTask?.cancel()
            dragExitTask = nil
            fileTrashTask?.cancel()
            fileTrashReady = false
            fileDropPhase = .hovering

            let task = DispatchWorkItem { [weak self] in
                guard let self, self.fileDropPhase.isReceiving else { return }
                self.fileTrashReady = true
                self.fileDropPhase = .trashArmed
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
    /// trash was armed, which left `fileDropPhase` stuck on `.trashArmed` after a
    /// drag that hovered long enough and then left without dropping. Both `cancel()`
    /// and `triggerReleased()` require `.idle`, so the ring became impossible to
    /// dismiss.
    private func scheduleDragExitReset() {
        dragExitTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self, self.fileDropPhase != .completing else { return }
            self.fileTrashReady = false
            self.fileDropPhase = .idle
        }
        dragExitTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbitConfig.fileDragExitGrace, execute: task)
    }

    func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let shouldTrash = fileTrashReady
        dragExitTask?.cancel()
        dragExitTask = nil
        fileTrashTask?.cancel()
        fileTrashTask = nil
        fileDropPhase = .completing

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
            self.fileDropPhase = .idle
            guard !urls.isEmpty else {
                self.onCancel?()
                return
            }

            if shouldTrash {
                for url in urls {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            } else if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
            }

            // The file operation owns the ring's lifetime. This also handles
            // the case where the user releases the trigger key while Finder is
            // still delivering the dropped URL asynchronously.
            self.onCancel?()
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
        }
    }
}

struct OrbitRingView: View {
    @ObservedObject var model: OrbitRingViewModel

    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: -model.previewOverlap) {
            ringCanvas

            if model.showsPreview {
                OrbitPreviewPanel(model: model)
                    .frame(width: model.previewPanelWidth)
            }
        }
        .frame(width: model.panelSize.width, height: model.panelSize.height)
        .scaleEffect(hasAppeared ? 1 : 0.9)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    private var ringCanvas: some View {
        ZStack {
            ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                let basePosition = model.position(for: index)
                OrbitAppCard(
                    app: app,
                    cardNumber: index + 1,
                    angle: model.angle(for: index),
                    isSelected: model.selectedID == app.id,
                    isDragging: model.draggedAppID == app.id,
                    isDissolving: model.dissolvingAppID == app.id || model.bulkDissolvingAppIDs.contains(app.id),
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
                    get: { model.fileDropPhase.isReceiving },
                    set: { model.setFileDragTargeted($0) }
                ),
                onCancel: { model.cancel() },
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
        // Center the group on the visible part of the panel rather than on the
        // panel itself, whose left edge sits under the fan.
        .offset(x: model.previewOverlap / 2)
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
        app: AppInfo? = nil,
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
        .frame(maxWidth: 360)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .offset(x: model.previewOverlap / 2)
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
            Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
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
    let app: AppInfo
    let cardNumber: Int
    /// Where the card sits on the ring, in radians (0 = 3 o'clock).
    let angle: Double
    let isSelected: Bool
    let isDragging: Bool
    let isDissolving: Bool
    let dragOffset: CGSize
    let onSelect: () -> Void
    let onHoverSelect: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var dissolveProgress = 0.0

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
        if OrbitConfig.letterShortcutsEnabled, let firstLetter = app.firstLetter {
            hints.append(String(firstLetter).lowercased())
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
        .opacity(isDissolving ? 0.35 : 1)
        // Particles are drawn in unrotated screen space, so aim them straight
        // at the ring center rather than at the card's own bottom edge.
        .pixelDissolve(progress: dissolveProgress, blackHoleDirection: angle + .pi)
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
        .onChange(of: isDissolving) { _, newValue in
            if newValue {
                withAnimation(.easeIn(duration: OrbitConfig.dissolveDuration)) {
                    dissolveProgress = 1
                }
            } else {
                dissolveProgress = 0
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
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(centerFill)
                            .frame(
                                width: OrbitConfig.centerRadius * 2,
                                height: OrbitConfig.centerRadius * 2
                            )
                            .overlay(Circle().stroke(centerStroke, lineWidth: 2))

                        Image(systemName: centerIcon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(centerIconColor)
                    }

                    Text(centerLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onTapGesture {
            if mode != .quit && mode != .cleanup && mode != .trash && mode != .share {
                onCancel()
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
        }
    }

    private var centerFill: Color {
        switch mode {
        case .cancel: .black.opacity(0.82)
        case .confirm: OrbitPalette.burgundy.opacity(0.92)
        case .quit, .trash: .black
        case .cleanup: .black.opacity(0.9)
        case .share: OrbitPalette.denim.opacity(0.96)
        }
    }

    private var centerStroke: Color {
        switch mode {
        case .cancel: .white.opacity(0.65)
        case .confirm: OrbitPalette.burgundy
        case .quit, .trash: OrbitPalette.coral
        case .cleanup: OrbitPalette.burgundy
        case .share: OrbitPalette.burgundy.opacity(0.65)
        }
    }

    private var centerIconColor: Color {
        mode == .share ? OrbitPalette.burgundy : .white
    }
}
