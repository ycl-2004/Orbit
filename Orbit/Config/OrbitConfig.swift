//
//  OrbitConfig.swift
//  Orbit
//
//  Runtime configuration shared by the menu bar app and the ring UI.
//

import AppKit
import Foundation
import SwiftUI

enum CardSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("cardSize.\(rawValue)", comment: "Card size name")
    }

    var dimension: CGFloat {
        switch self {
        case .small: 88
        case .medium: 104
        case .large: 120
        case .extraLarge: 136
        }
    }

    /// Cards are portrait so the icon can sit above the shortcut hint.
    var height: CGFloat {
        (dimension * 1.2).rounded()
    }

    var iconDimension: CGFloat {
        dimension * 0.47
    }
}

/// Where the ring appears when Orbit is summoned.
enum RingPlacement: String, CaseIterable, Identifiable {
    /// Centered on the screen that currently holds the cursor.
    case screenCenter
    /// Centered on the cursor itself, clamped to the visible frame.
    case cursor

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("ringPlacement.\(rawValue)", comment: "Ring placement name")
    }
}

enum OrbitConfig {
    enum CardMaterial: String, CaseIterable, Identifiable {
        case white
        case black
        case system

        var id: String { rawValue }

        var localizedName: String {
            NSLocalizedString("cardFinish.\(rawValue)", comment: "Card finish name")
        }
    }

    private static let defaults = UserDefaults.standard

    static var longPressThreshold: Double {
        get {
            let value = defaults.object(forKey: "longPressThreshold") as? Double ?? 150
            return min(max(value, 100), 300)
        }
        set {
            defaults.set(min(max(newValue, 100), 300), forKey: "longPressThreshold")
        }
    }

    /// 唤出 Orbit 的那个键。
    ///
    /// `.disabled` is deliberately not a legal answer here. It is a legal value of
    /// the type — the clear-selection shortcut uses it to mean "off" — but as the
    /// trigger it would make the ring unsummonable, since `handleFlagsChanged`
    /// returns immediately on it. Healing the value on read also rescues anyone who
    /// managed to store it before the settings picker stopped offering it.
    static var triggerModifier: TriggerModifier {
        get {
            guard let rawValue = defaults.string(forKey: "triggerModifier"),
                  let modifier = TriggerModifier(rawValue: rawValue),
                  modifier != .disabled else {
                return .option
            }
            return modifier
        }
        set {
            let safeValue = newValue == .disabled ? .option : newValue
            defaults.set(safeValue.rawValue, forKey: "triggerModifier")
        }
    }

    static var cardSize: CardSize {
        get {
            guard let rawValue = defaults.string(forKey: "cardSize"),
                  let size = CardSize(rawValue: rawValue) else {
                return .large
            }
            return size
        }
        set {
            defaults.set(newValue.rawValue, forKey: "cardSize")
        }
    }

    /// Tapped while the ring is open, this clears the current selection so
    /// releasing the trigger dismisses without switching apps. Never allowed
    /// to be the trigger key itself.
    static var clearSelectionModifier: TriggerModifier {
        get {
            let stored = defaults.string(forKey: "clearSelectionModifier")
                .flatMap(TriggerModifier.init(rawValue:)) ?? .shift
            return stored == triggerModifier ? .disabled : stored
        }
        set {
            defaults.set(newValue.rawValue, forKey: "clearSelectionModifier")
        }
    }

    /// Letter matching is opt-in so the default interaction stays focused on
    /// the arrow keys. The setting is intentionally independent from the
    /// numeric shortcuts so users can choose either style.
    static var letterShortcutsEnabled: Bool {
        get { defaults.bool(forKey: "letterShortcutsEnabled") }
        set { defaults.set(newValue, forKey: "letterShortcutsEnabled") }
    }

    /// Number-to-card shortcuts are opt-in and only cover the visible cards
    /// addressed by the 1–9 keys.
    static var numericShortcutsEnabled: Bool {
        get { defaults.bool(forKey: "numericShortcutsEnabled") }
        set { defaults.set(newValue, forKey: "numericShortcutsEnabled") }
    }

    /// Dock 给每个运行中的进程都点一个小圆点，哪怕它一个窗口都没开。Orbit 不该
    /// 照抄这个口径：切到一个没有窗口的应用，屏幕上什么也不会发生，预览面板也只
    /// 能显示"没有窗口可预览"。
    ///
    /// On by default, which is why this reads through `object(forKey:)` rather
    /// than `bool(forKey:)` — the latter answers `false` for a key nobody has
    /// written yet, and that is the opposite of what we want on first launch.
    static var hideWindowlessApps: Bool {
        get { defaults.object(forKey: "hideWindowlessApps") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hideWindowlessApps") }
    }

    /// Orbit can be represented as a card in its own ring, but some users
    /// prefer the ring to contain only other running apps. Keep the card on by
    /// default and persist the choice alongside the other ring filters.
    static var showOrbitCard: Bool {
        get { defaults.object(forKey: "showOrbitCard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showOrbitCard") }
    }

    /// Opt-in because window capture needs the Screen Recording permission,
    /// which the ring itself does not.
    static var windowPreviewEnabled: Bool {
        get { defaults.bool(forKey: "windowPreviewEnabled") }
        set { defaults.set(newValue, forKey: "windowPreviewEnabled") }
    }

    static var ringPlacement: RingPlacement {
        get {
            guard let rawValue = defaults.string(forKey: "ringPlacement"),
                  let placement = RingPlacement(rawValue: rawValue) else {
                return .screenCenter
            }
            return placement
        }
        set {
            defaults.set(newValue.rawValue, forKey: "ringPlacement")
        }
    }

    static var cardMaterial: CardMaterial {
        get {
            guard let rawValue = defaults.string(forKey: "cardMaterial"),
                  let material = CardMaterial(rawValue: rawValue) else {
                return .white
            }
            return material
        }
        set {
            defaults.set(newValue.rawValue, forKey: "cardMaterial")
        }
    }

    /// The user-selectable Orbit accent. Stored as a secure, sRGB NSColor
    /// archive because SwiftUI Color itself is environment-resolved rather
    /// than a stable UserDefaults value.
    static var accentColor: Color {
        get { color(forKey: "accentColor") ?? OrbitPalette.defaultBurgundy }
        set { setColor(newValue, forKey: "accentColor") }
    }

    /// 圆环背后那块圆盘要不要显示。
    ///
    /// Only the ring's own backdrop is optional. The preview panel's surface is
    /// what makes a captured window legible against an arbitrary desktop, so it
    /// is not a matter of taste and gets no switch.
    static var ringBackdropEnabled: Bool {
        get { defaults.object(forKey: "ringBackdropEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ringBackdropEnabled") }
    }

    /// 圆盘自己的颜色，跟 accent 分开存。
    ///
    /// The accent also paints the selected card's hairline, the confirm hub and
    /// the preview's icons, where it has to stay saturated enough to read as a
    /// deliberate mark. The backdrop is a large, very transparent wash, and the
    /// colour that works for one rarely works for the other. Falling back to
    /// the accent keeps an untouched install looking exactly as it did.
    static var ringBackdropColor: Color {
        get { color(forKey: "ringBackdropColor") ?? accentColor }
        set { setColor(newValue, forKey: "ringBackdropColor") }
    }

    /// Whether the backdrop colour has been chosen on its own rather than
    /// inherited from the accent. The settings window needs this to know when
    /// its swatch has to follow an accent change.
    static var hasCustomRingBackdropColor: Bool {
        defaults.data(forKey: "ringBackdropColor") != nil
    }

    private static func color(forKey key: String) -> Color? {
        guard let data = defaults.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: data
              ) else {
            return nil
        }
        return Color(nsColor: color)
    }

    private static func setColor(_ newValue: Color, forKey key: String) {
        let color = NSColor(newValue).usingColorSpace(.sRGB) ?? NSColor(newValue)
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: color,
            requiringSecureCoding: true
        ) else {
            return
        }
        defaults.set(data, forKey: key)
    }

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
        let spacing = cardSize.dimension * 0.86
        let byOverlap = spacing / CGFloat(ringStep(cardCount: cardCount))
        let compactScale: CGFloat = cardCount <= 4 ? 0.78 : 1
        // Keep the center clear even in compact mode: the card's inner edge
        // gets real breathing room beyond the hub rather than crowding it.
        let minimum = centerFootprintRadius + cardSize.height * 0.5 + centerClearance
        return max(minimum, byOverlap * compactScale)
    }

    static var centerRadius: CGFloat {
        (cardSize.dimension * 0.42).rounded()
    }

    /// 中心控件真正占掉的半径：圆盘本身，加上它下面那颗状态标签。
    ///
    /// The hub is a `VStack` — the circle with its Cancel/Confirm label under
    /// it — centred on the ring's centre, so the label reaches further down
    /// than the circle reaches in any other direction. Clearance measured
    /// against `centerRadius` alone therefore lies: it reads as comfortable on
    /// the sides while the bottom of the fan sits right on top of the label.
    static var centerFootprintRadius: CGFloat {
        let labelHeight: CGFloat = 27
        let labelSpacing: CGFloat = 8
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

    /// Canvas has to hold the outermost card corner plus its shadow and the
    /// scale-up applied to the selected card.
    static func ringCanvasSize(cardCount: Int) -> CGFloat {
        (ringRadius(cardCount: cardCount) + cardSize.height * 0.5 + 72) * 2
    }

    /// 磨砂轨道的径向厚度：一张卡片那么宽，不是一张卡片那么高。
    ///
    /// 轨道是卡片脚下的一条环形跑道，不是一块把卡片整个裹住的玻璃。Sizing it to
    /// clear a card's corners means the band has to be wider than a card is
    /// tall, and at that width it stops reading as a track and starts reading
    /// as the plate it replaced — it was the thickness, not the tint, that made
    /// the old backdrop feel like it took over the screen. A card is rotated so
    /// its long axis points at the hub, so a band one card *wide* leaves the
    /// top and bottom of each card standing slightly proud of it, which is what
    /// gives the ring its depth and keeps the hollow in the middle wide open.
    static var ringTrackThickness: CGFloat {
        cardSize.dimension
    }

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
        let overhang = cardSize.dimension * 0.55 - ringTrackThickness / 2 + 8
        return Double(max(overhang, 8) / ringRadius(cardCount: cardCount))
    }

    /// 轨道最外圈到中心的距离，也就是窗口排版必须让出来的地方。
    static func ringBackdropRadius(cardCount: Int) -> CGFloat {
        ringRadius(cardCount: cardCount) + ringTrackThickness / 2
    }

    /// Widest the preview half is allowed to get.
    static let previewPanelMaximumWidth: CGFloat = 1040
    /// Breathing room around the preview inside the half it owns.
    static let previewGap: CGFloat = 28
    /// Clearance the ring window keeps from the edges of the visible frame.
    static let screenMargin: CGFloat = 24
    /// 窗口占可见区域宽度的比例。
    ///
    /// The ring and the preview each sit at the middle of their own half, so
    /// the window's width is also the distance between them: at full width the
    /// disc gets pushed into the screen's left corner. 0.88 lands the disc near
    /// the 28% mark and the carousel near 72%, which reads as one centred pair
    /// with the ring clear of the corner.
    static let layoutWidthRatio: CGFloat = 0.88
    /// Upper bound on the foreground card in the window carousel. The half it
    /// sits in narrows it further on a small display.
    static let previewCardMaximumWidth: CGFloat = 600

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

    /// Capture cost scales with area, and the ring is only on screen for as
    /// long as a key is held. This caps what a Retina foreground card can ask
    /// for.
    static let previewMaximumCaptureWidth = 1200

    /// Capture at the size the foreground carousel card really occupies, in
    /// device pixels. Every window takes a turn in front, so they are all
    /// captured for that slot rather than for the smaller neighbouring ones.
    static var previewCaptureWidth: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return min(Int((previewCardMaximumWidth * scale).rounded()), previewMaximumCaptureWidth)
    }

    /// 小到这个尺寸以下的窗口不算「一个真的窗口」。
    ///
    /// Autofill popovers, tooltip shadows and the placeholder surfaces apps keep
    /// around all come back as real entries in the window list. Both the ring's
    /// app list and the preview's window list measure against this same number,
    /// so a card never promises a thumbnail the preview then refuses to show.
    static let minimumRealWindowSize = CGSize(width: 200, height: 120)

    static let maxVisibleApps = 12
    static let dissolveParticleCount = 72
    static let dissolveDuration: TimeInterval = 0.55
    static let terminateGracePeriod: TimeInterval = 0.45
    static let fileTrashHoldDuration: TimeInterval = 0.9

    /// 拖拽离开中心之后，等这么久再把拖放状态复位。
    ///
    /// Long enough that a drop landing right after the "no longer targeted"
    /// callback still finds the trash armed, short enough that a drag which
    /// simply left never leaves the ring stuck in a state it cannot be
    /// dismissed from.
    static let fileDragExitGrace: TimeInterval = 0.2
}
