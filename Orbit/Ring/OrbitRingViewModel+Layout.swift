//
//  OrbitRingViewModel+Layout.swift
//  Orbit
//
//  Where everything on the ring sits. Pure geometry: it reads the model's
//  per-showing values (`layoutCount`, `visibleFrame`, `showsPreview`) and
//  never changes state.
//

import AppKit

extension OrbitRingViewModel {
    var ringRadius: CGFloat {
        OrbitPreferences.ringRadius(cardCount: layoutCount)
    }

    var canvasSize: CGFloat {
        OrbitPreferences.ringCanvasSize(cardCount: layoutCount)
    }

    /// The highest-value recent destination is the ring's spatial anchor: index
    /// zero always sits at 12 o'clock, upright. It is another window of the
    /// current app when available, otherwise the previous application. Stable
    /// placement matters more than centring a short fan.
    private static let fanStartAngle = -Double.pi / 2

    /// MRU order walks from 12 o'clock down the left side first. The direction
    /// stays identical with and without Window Preview, so repeated keyboard
    /// steps build one spatial memory instead of mirroring the sequence.
    func angle(for index: Int) -> Double {
        let step = OrbitPreferences.ringStep(cardCount: layoutCount)
        return Self.fanStartAngle - step * Double(index)
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
        OrbitPreferences.ringBackdropRadius(cardCount: layoutCount) * 2
    }

    /// 轨道要盖住的那段角度：正好是首尾两张卡片之间，两端各多留一点。
    ///
    /// The track follows the fixed top anchor through the final card. Angles
    /// decrease as MRU order advances, while the backdrop shape expects an
    /// ascending range, so the last card supplies the lower bound.
    var backdropArc: ClosedRange<Double> {
        let span = apps.count > 1
            ? OrbitPreferences.ringStep(cardCount: layoutCount) * Double(apps.count - 1)
            : 0
        let padding = OrbitPreferences.ringTrackEndPadding(cardCount: layoutCount)
        return (Self.fanStartAngle - span - padding)...(Self.fanStartAngle + padding)
    }

    /// 轨道线的半径。
    var orbitTrailRadius: CGFloat {
        OrbitPreferences.orbitTrailRadius(cardCount: layoutCount)
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
        guard layoutCount > 0 else { return .zero }
        var sumX = 0.0
        var sumY = 0.0
        for index in 0 ..< layoutCount {
            let angle = angle(for: index)
            sumX += cos(angle)
            sumY += sin(angle)
        }
        let count = Double(layoutCount)
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
        let fanReach = OrbitPreferences.ringBackdropRadius(cardCount: layoutCount)
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
}
