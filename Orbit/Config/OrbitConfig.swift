//
//  OrbitConfig.swift
//  Orbit
//
//  Runtime configuration shared by the menu bar app and the ring UI.
//

import AppKit
import Foundation

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

    static var triggerModifier: TriggerModifier {
        get {
            guard let rawValue = defaults.string(forKey: "triggerModifier"),
                  let modifier = TriggerModifier(rawValue: rawValue) else {
                return .option
            }
            return modifier
        }
        set {
            defaults.set(newValue.rawValue, forKey: "triggerModifier")
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

    static func ringStep(cardCount: Int) -> Double {
        guard cardCount > 1 else { return ringPreferredStep }
        return min(ringPreferredStep, ringMaximumSpan / Double(cardCount - 1))
    }

    /// Distance from the ring center to the center of a card. Sized so the arc
    /// between two cards stays shorter than a card is wide.
    static func ringRadius(cardCount: Int) -> CGFloat {
        let spacing = cardSize.dimension * 0.86
        let byOverlap = spacing / CGFloat(ringStep(cardCount: cardCount))
        // The hollow center is what makes the fan read as a ring: keep its
        // radius at roughly 0.7 of a card height, as in the reference layout.
        let minimum = cardSize.height * 1.15
        return max(minimum, byOverlap)
    }

    static var centerRadius: CGFloat {
        (cardSize.dimension * 0.36).rounded()
    }

    /// File drops need a forgiving target: a Finder drag should not require
    /// pixel-perfect aim at the compact visual hub. Keep the target inside the
    /// ring's hollow center so it does not steal the surrounding app cards.
    static var centerDropRadius: CGFloat {
        centerRadius + 56
    }

    /// Canvas has to hold the outermost card corner plus its shadow and the
    /// scale-up applied to the selected card.
    static func ringCanvasSize(cardCount: Int) -> CGFloat {
        (ringRadius(cardCount: cardCount) + cardSize.height * 0.5 + 72) * 2
    }

    /// Widest the preview panel is allowed to get.
    static let previewPanelMaximumWidth: CGFloat = 1040
    /// Breathing room between the fan's outer edge and the preview panel.
    static let previewGap: CGFloat = 56

    /// The panel claims whatever the fan leaves on screen, up to its maximum.
    /// A fixed width cannot serve both ends of this: the ring canvas grows
    /// with the number of cards and with the card size setting, so the same
    /// 720pt that fits beside a twelve-card fan of extra-large cards leaves
    /// the carousel needlessly small beside a five-card one.
    static func previewPanelWidth(cardCount: Int, overlap: CGFloat) -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        // The panel overlaps the canvas, so that much of it costs no width.
        let available = screenWidth - 40 - ringCanvasSize(cardCount: cardCount) + overlap
        return max(420, min(previewPanelMaximumWidth, available))
    }
    /// Upper bound on the foreground card in the window carousel. The panel
    /// narrows it further when the fan leaves less room.
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
}
