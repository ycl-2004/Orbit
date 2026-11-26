//
//  OrbitTuning.swift
//  Orbit
//
//  Fixed geometry and timing: the numbers the ring is drawn and timed with.
//  Nothing here is stored or user-facing; `OrbitPreferences.swift` holds the
//  settings, and the values here read `cardScale` from it where size depends
//  on the chosen card size.
//

import AppKit

extension OrbitPreferences {
    // Geometry is driven by one rule: neighbouring cards always overlap by the
    // same amount, like a spread deck. Cards are placed a fixed arc length
    // apart, so the radius grows with the number of cards instead of the fan
    // getting denser.

    /// Widest the fan is allowed to open (270°), leaving a gap on the left.
    static let ringMaximumSpan = 1.5 * Double.pi
    /// Angle between two neighbouring cards when there is room for it (40°).
    /// At this step a typical set of apps closes into a C rather than a
    /// shallow arc, and the rotation difference alone makes the corners
    /// overlap the way a spread deck does.
    static let ringPreferredStep = Double.pi * 40 / 180
    /// A small fan should read as a compact cluster rather than a sparse arc.
    /// This only applies to the four-card case and below; a fuller ring keeps
    /// the normal 40° rhythm.
    static let compactRingStep = Double.pi * 36 / 180

    static func ringStep(cardCount: Int) -> Double {
        guard cardCount > 1 else { return ringPreferredStep }
        let preferred = cardCount <= 4 ? compactRingStep : ringPreferredStep
        return min(preferred, ringMaximumSpan / Double(cardCount - 1))
    }

    /// Distance from the ring center to the center of a card. Sized so the arc
    /// between two cards stays shorter than a card is wide.
    static func ringRadius(cardCount: Int) -> CGFloat {
        let spacing = cardScale.dimension * 0.86
        let byOverlap = spacing / CGFloat(ringStep(cardCount: cardCount))
        let compactScale: CGFloat = cardCount <= 4 ? 0.78 : 1
        // Keep the center clear even in compact mode: the card's inner edge
        // gets real breathing room beyond the hub rather than crowding it.
        let minimum = centerFootprintRadius + cardScale.height * 0.5 + centerClearance
        return max(minimum, byOverlap * compactScale)
    }

    /// 中心那颗圆点看得见的半径。
    ///
    /// Deliberately smaller than the target you can hit: the hub is an anchor,
    /// not the loudest thing on the ring, and `centerDropRadius` keeps a file
    /// drag just as forgiving as it was.
    static var centerRadius: CGFloat {
        (cardScale.dimension * 0.39).rounded()
    }

    /// 中心控件真正占掉的半径：圆盘本身，加上它下面那颗状态标签。
    ///
    /// The hub is a `VStack` — the circle with its Cancel/Confirm label under
    /// it — centred on the ring's centre, so the label reaches further down
    /// than the circle reaches in any other direction. Clearance measured
    /// against `centerRadius` alone therefore lies: it reads as comfortable on
    /// the sides while the bottom of the fan sits right on top of the label.
    static var centerFootprintRadius: CGFloat {
        let labelHeight: CGFloat = 25
        let labelSpacing: CGFloat = 10
        return (centerRadius * 2 + labelSpacing + labelHeight) / 2
    }

    /// Empty space between the hub's footprint and the nearest card edge.
    ///
    /// The fan keeps overlapping at this radius even though the arc between
    /// two cards grows past a card's width: neighbours differ by a full
    /// `ringStep` of rotation, and a rotated card reaches its half-diagonal
    /// sideways rather than its half-width.
    static let centerClearance: CGFloat = 34

    /// File drops need a forgiving target: a Finder drag should not require
    /// pixel-perfect aim at the compact visual hub. Keep the target inside the
    /// ring's hollow center so it does not steal the surrounding app cards.
    static var centerDropRadius: CGFloat {
        centerRadius + 60
    }

    /// 拖着一张卡片，卡片中心进到离星芯多近，中心就变成「退出」。
    ///
    /// Tighter than the file target: a card is large and starts out on the
    /// ring, so a generous reach would arm the quit while the card is still
    /// visibly among its neighbours.
    static var centerQuitReach: CGFloat {
        centerRadius + 28
    }

    /// Canvas has to hold the outermost card corner plus its shadow and the
    /// scale-up applied to the selected card.
    static func ringCanvasSize(cardCount: Int) -> CGFloat {
        (ringRadius(cardCount: cardCount) + cardScale.height * 0.5 + 72) * 2
    }

    /// 卡片脚下那道辉光的径向宽度。
    ///
    /// Wider than the band it replaced rather than narrower: a glow with no edge
    /// cannot be "covered" the way a plate could, so its size is free to be
    /// chosen for how far the light should reach instead of for how much of it
    /// will survive behind the cards. Reaching past a card's own height is what
    /// makes the fan look like it is standing *in* the light rather than on top
    /// of a shape.
    static var ringTrackThickness: CGFloat {
        cardScale.dimension * 0.95
    }

    /// 卡片跟着扇面转多少 —— 1 是完全跟随，0 是永远正立。
    ///
    /// 回到 1。上一版按「一手真牌旋转远小于展开」的类比取了 0.5，那个类比对，但
    /// 它描述的是一手*被握着*的牌 —— 有一只手定义了基准。The fan has no hand.
    /// Its baseline is the circle itself, and a card at half-follow lines up
    /// with neither the circle nor the screen: every card sits at its own
    /// unrelated angle, which is what reads as spilled. Full follow gives every
    /// card the same relationship to the hub, and a rosette where the rule is
    /// visible is easier to scan than a spread where each tile is individually
    /// closer to upright.
    static let cardRotationFollow: Double = 1.0

    /// 轨道线的半径：卡片内缘再往里一点，落在中心和扇面之间的空白上。
    ///
    /// Set from the card's inner edge rather than as a fraction of the radius so
    /// the clearance stays the same at every card size. Clamped against the hub
    /// so a compact fan — whose cards already sit close in — cannot push the
    /// line onto the hub's own footprint.
    static func orbitTrailRadius(cardCount: Int) -> CGFloat {
        let innerEdge = ringRadius(cardCount: cardCount) - cardScale.height * 0.5
        return max(centerFootprintRadius + 12, innerEdge - 16)
    }

    /// 取消时卡片收回中心要花多久，窗口撤除等的就是这段。
    ///
    /// Long enough to read as the fan folding back rather than as a stutter,
    /// short enough that Escape still feels like Escape. The cards' own spring
    /// is a touch longer than this on purpose — the window leaves while the last
    /// of the motion is still settling, which no one sees, and waiting for the
    /// spring to fully rest would be the part that felt slow.
    static let collapseDuration: TimeInterval = 0.2

    /// 选中的卡片被中心"引力"拉近多少。
    ///
    /// Selection already reads through lift and scale; this is what ties it to
    /// the hub rather than leaving it as a card that happens to be bigger. It
    /// has to stay small — far enough and the card breaks the arc its
    /// neighbours are still standing on.
    static let selectionGravityPull: CGFloat = 12

    /// 轨道在扇面两端各多走出去的角度。
    ///
    /// The band ends in a round cap of half its thickness, so a cap centred on
    /// the last card's own centre would stop short of that card's outer edge
    /// and leave it hanging off the end. Sliding the centre out by the
    /// difference lands the cap just past the card — far enough that the track
    /// runs out from under the fan rather than being cut off at it, close
    /// enough that no empty glass trails behind the last app. This is also what
    /// gives a single-app ring a band at all, since its fan spans no angle.
    static func ringTrackEndPadding(cardCount: Int) -> Double {
        let overhang = cardScale.dimension * 0.55 - ringTrackThickness / 2 + 8
        return Double(max(overhang, 8) / ringRadius(cardCount: cardCount))
    }

    /// 轨道最外圈到中心的距离，也就是窗口排版必须让出来的地方。
    static func ringBackdropRadius(cardCount: Int) -> CGFloat {
        ringRadius(cardCount: cardCount) + ringTrackThickness / 2
    }

    /// Widest the preview half is allowed to get.
    static let previewPanelMaximumWidth: CGFloat = 1040
    /// Breathing room around the preview inside the half it owns.
    static let previewGap: CGFloat = 24
    /// Clearance the ring window keeps from the edges of the visible frame.
    static let screenMargin: CGFloat = 24
    /// 窗口占可见区域宽度的比例 —— 也就是两半之间隔多远。
    ///
    /// The ring and the preview each sit at the middle of their own half, so the
    /// window's width is also the distance between them. 0.88 kept the ring out
    /// of the corner but left a screen's worth of untouched wallpaper between
    /// the fan and the carousel, and two objects that far apart stop reading as
    /// one thing. Pulling it in, together with the centroid correction in
    /// `fanCentroid`, closes that gap from both sides at once.
    static let layoutWidthRatio: CGFloat = 0.74

    /// 预览卡片按哪个比例算大小。
    ///
    /// Deliberately not `layoutWidthRatio`: that one now says how far apart the
    /// halves sit, and tying the carousel's size to it would have shrunk every
    /// thumbnail the moment the pair was pulled together. Holding it at the old
    /// ratio is what keeps a preview scale of 1.0 the same number of pixels it
    /// has always been.
    static let previewSizingRatio: CGFloat = 0.82
    /// Upper bound on the foreground card in the window carousel. The half it
    /// sits in narrows it further on a small display.
    static let previewCardMaximumWidth: CGFloat = 560

    /// Carousel geometry: a neighbour sits `previewSideOffsetRatio` of a card
    /// width out from the middle and is drawn at `previewSideScale`, so its
    /// outer edge lands at the sum of the two — already past the front card's
    /// own half — and the group spans twice that in cards. The front card is
    /// inside that reach, not added to it.
    static let previewSideOffsetRatio: CGFloat = 0.38
    static let previewSideScale: CGFloat = 0.74
    static var previewCarouselSpan: CGFloat {
        2 * (previewSideOffsetRatio + previewSideScale / 2)
    }

    /// The stage keeps one shape for every window, so the page control below
    /// it cannot shift as the selection moves between a tall window and a wide
    /// one. Each capture is fitted inside at its own ratio.
    static let previewStageAspectRatio: CGFloat = 16.0 / 10.0

    /// Largest number of window thumbnails shown for one app.
    static let maxVisiblePreviews = 6

    /// 一次召唤最多截多少个窗口 —— 席位之外还允许试几个，仅此而已。
    ///
    /// Capture stops as soon as `maxVisiblePreviews` windows have come back with
    /// real content, so this ceiling only matters for an app whose windows are
    /// *all* flat helper surfaces: those get dropped after capture, and without
    /// a ceiling such an app would be walked window by window to the end of the
    /// list looking for content that is not there.
    static let maxPreviewCaptures = maxVisiblePreviews * 2

    /// Capture cost scales with area, and the ring is only on screen for as
    /// long as a key is held. This caps what a Retina foreground card can ask
    /// for.
    static let previewMaximumCaptureWidth = 1200

    /// Capture at the size the foreground carousel card really occupies, in
    /// device pixels. Every window takes a turn in front, so they are all
    /// captured for that slot rather than for the smaller neighbouring ones.
    ///
    /// The scale is the *target screen's*, passed in rather than read from
    /// `NSScreen.main`: the ring can be summoned onto a display whose density
    /// differs from the main one, and guessing wrong costs either memory or
    /// sharpness.
    static func previewCaptureWidth(scale: CGFloat) -> Int {
        // 用户放大了预览就得多采样，否则放大出来的是一张糊图。上限仍然由
        // `previewMaximumCaptureWidth` 兜着。
        let target = previewCardMaximumWidth * previewScale * scale
        return min(Int(target.rounded()), previewMaximumCaptureWidth)
    }

    /// 小到这个尺寸以下的窗口不算「一个真的窗口」。
    ///
    /// Autofill popovers, tooltip shadows and the placeholder surfaces apps keep
    /// around all come back as real entries in the window list. Both the ring's
    /// app list and the preview's window list measure against this same number,
    /// so a card never promises a thumbnail the preview then refuses to show.
    static let minimumRealWindowSize = CGSize(width: 200, height: 120)

    /// 一次切换的兜底激活最多可以迟到多久还算数。
    ///
    /// Every step of a switch is meant to land inside the beat after the ring
    /// closes. The one step that can outlive it is the Apple Events fallback:
    /// its first contact with an app raises the system's Automation dialog and
    /// blocks until that dialog is answered. Past this point the switch is no
    /// longer what the person is doing, and activating an app then is an
    /// interruption rather than a completion.
    static let maximumSwitchFallbackDelay: TimeInterval = 3

    /// 在一个应用的辅助功能窗口列表里找目标窗，最多花多久。
    ///
    /// The search runs on the main thread, which the event tap shares. A
    /// healthy app answers the whole walk in a few milliseconds; past this, the
    /// app is stalling and the next switch stage is the better bet.
    static let axWindowSearchBudget: TimeInterval = 0.5

    /// 每一次辅助功能往返最多等多久。装在系统级对象上，对这个进程发出的所有 AX
    /// 调用生效；个别调用（Window 菜单那一下）会自己要更长。
    static let accessibilityMessagingTimeout: Float = 0.4

    /// 等辅助功能权限时多久看一次。一次检查几乎不花什么，慢一点只是为了不吵。
    static let accessibilityPollInterval: TimeInterval = 1.5

    /// 切换发出之后，隔多久回头问一次窗口服务「落在那扇窗上了吗」。
    ///
    /// Polled rather than checked once, because the two cases have opposite
    /// needs: a switch inside one Space is done almost immediately, while
    /// crossing to a fullscreen Space runs an animation first. Polling answers
    /// the fast case fast and still gives the slow one room.
    static let switchVerificationPollInterval: TimeInterval = 0.12

    /// 等到这里还没落到目标窗上，就认定这一级没做成，降到下一级。
    ///
    /// 比一次 Space 切换动画（约 0.5 秒）宽出一截 —— 判早了会把一次正在路上的
    /// 正确切换当成失败，紧接着再切一次，用户看到的是画面跳两下。
    static let switchVerificationTimeout: TimeInterval = 0.9

    static let maxVisibleApps = 12
    static let dispersionParticleCount = 72
    static let dispersionDuration: TimeInterval = 0.55
    static let quitGracePeriod: TimeInterval = 0.45
    static let fileTrashHoldDuration: TimeInterval = 0.9

    /// 拖拽离开中心之后，等这么久再把拖放状态复位。
    ///
    /// Long enough that a drop landing right after the "no longer targeted"
    /// callback still finds the trash armed, short enough that a drag which
    /// simply left never leaves the ring stuck in a state it cannot be
    /// dismissed from.
    static let fileDragExitGrace: TimeInterval = 0.2

    /// 拖放失败时，中心把「没成」这件事挂多久。
    ///
    /// Long enough to be read at a glance, short enough that it never becomes
    /// something to dismiss. A deferred close waits this out rather than
    /// closing on top of the notice.
    static let fileDropFailureNoticeDuration: TimeInterval = 2.0
}
