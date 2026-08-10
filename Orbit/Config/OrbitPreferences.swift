//
//  OrbitPreferences.swift
//  Orbit
//
//  Runtime configuration shared by the menu bar app and the ring UI.
//

import AppKit
import Foundation
import SwiftUI

enum CardScale: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("cardScale.\(rawValue)", comment: "Card size name")
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

/// Whether the ring backdrop borrows the accent or has its own colour.
enum RingBackdropMode: String, CaseIterable, Identifiable {
    case followAccent
    case custom

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("ringBackdropMode.\(rawValue)", comment: "Ring backdrop colour source")
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

/// 卡片在环上按什么顺序排。
///
/// 两种模式都把"最近的切换目标"固定为第一张卡和 12 点钟锚点。当前应用有其他
/// 窗口时，这个目标是最近的另一扇窗口；否则才是刚才那个应用。`.recent` 让其余
/// 卡片继续按使用历史排列；`.alphabetical` 只把锚点之后的卡片按名称排列。
///
/// 两种模式都先按最近使用挑选并截取最多十二个应用；`.alphabetical` 只在挑选完成
/// 后保留第一张，再按名字摆其余卡片。名额和摆放是两件事。
enum RingOrder: String, CaseIterable, Identifiable {
    case recent
    case alphabetical

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("ringOrder.\(rawValue)", comment: "Ring order name")
    }
}

/// What the ring selects at the moment it opens. Cancel is intentionally the
/// default; quick switch is opt-in because releasing the summon shortcut then
/// performs an action immediately.
enum RingOpeningBehavior: String, CaseIterable, Identifiable {
    case cancel
    case quickSwitch

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("ringOpeningBehavior.\(rawValue)", comment: "Ring opening behavior")
    }
}

enum OrbitPreferences {
    enum CardFinish: String, CaseIterable, Identifiable {
        case white
        case black
        case system

        var id: String { rawValue }

        var localizedName: String {
            NSLocalizedString("cardFinish.\(rawValue)", comment: "Card finish name")
        }

        /// 整个召唤层该按哪种外观来画。`nil` = 跟系统。
        ///
        /// 这个设置的名字说的是卡片，但没有人是这么理解它的。Picking Black turned
        /// the cards dark and left the wash, the hub, the empty state and the
        /// preview panel light — a switcher assembled out of two different
        /// themes. Whoever reaches for it is choosing how the ring should look,
        /// so it has to decide the whole layer.
        ///
        /// Driving it through `NSAppearance` on the panels rather than threading
        /// a colour down every view: one property flips SwiftUI's `colorScheme`,
        /// `.primary` and `.secondary`, every system material, and
        /// `windowBackgroundColor` together. Anything hand-plumbed would drift
        /// apart again the first time a new surface was added.
        var appearanceName: NSAppearance.Name? {
            switch self {
            case .white: .aqua
            case .black: .darkAqua
            case .system: nil
            }
        }
    }

    /// 召唤层脚下那层地画到哪一步 —— 目前只有隐藏键，没有 UI。
    ///
    /// 这个开关是为了把「云」和「模糊」拆开看。The two have always shipped as one
    /// thing, so "the background is too heavy" could mean either: the visible
    /// blooms and pools, or the behind-window blur they sit on. Guessing costs a
    /// build and a look each time; a key costs one build and answers all three.
    ///
    /// 定下来之后这个 enum 应该被删掉，只留胜出的那一档。
    enum ScrimStyle: String {
        /// 模糊 + 暖影 + 两团柔光。
        case dusk
        /// 只留桌面模糊，云和压暗都不画。
        case blurOnly
        /// 整层不画，环直接落在桌面上。
        case none

        var drawsBlur: Bool { self != .none }
        var drawsGround: Bool { self == .dusk }
    }

    private static let defaults = UserDefaults.standard

    /// `defaults write app.orbit.local scrimStyle dusk|blurOnly|none`
    static var scrimStyle: ScrimStyle {
        guard let rawValue = defaults.string(forKey: "scrimStyle"),
              let style = ScrimStyle(rawValue: rawValue) else {
            return .dusk
        }
        return style
    }

    // MARK: - 旧版本设置迁移

    /// 1.5.1 及更早的版本用另一套键名存设置。升级上来的用户在磁盘上只有旧键，
    /// 直接读新键会让他们的触发键、卡片尺寸、欢迎页状态统统回到出厂值。
    ///
    /// 迁移一次就够，所以每个键都先看新键在不在：在，说明这台机器已经迁过（或者
    /// 本来就是新装），旧值不该再覆盖回去。搬完就把旧键删掉，下次启动这里什么也
    /// 不会做。
    ///
    /// 必须在任何一个属性被读到之前调用 —— `ApplicationDelegate` 在
    /// `applicationDidFinishLaunching` 的第一行调它。
    static func migrateStoredPreferences() {
        for (legacyKey, currentKey) in [
            ("longPressThreshold", "summonHoldDuration"),
            ("cardSize", "cardScale"),
            ("cardMaterial", "cardFinish"),
            ("hasSeenWelcome", "onboardingCompleted"),
            ("triggerModifier", "summonKey"),
        ] {
            defer { defaults.removeObject(forKey: legacyKey) }

            guard defaults.object(forKey: currentKey) == nil,
                  let legacyValue = defaults.object(forKey: legacyKey) else { continue }

            defaults.set(migratedValue(legacyValue), forKey: currentKey)
        }

        // 这个键名没变，但它存的是 `ShortcutKey.rawValue`，而那套拼写变了。
        if let stored = defaults.string(forKey: "clearSelectionModifier"),
           let renamed = renamedShortcutSpelling(stored) {
            defaults.set(renamed, forKey: "clearSelectionModifier")
        }
    }

    /// 修饰键的存储拼写在同一次改名里换过，所以搬键的时候顺带把值也翻译一遍。
    private static func migratedValue(_ legacyValue: Any) -> Any {
        guard let spelling = legacyValue as? String,
              let renamed = renamedShortcutSpelling(spelling) else {
            return legacyValue
        }
        return renamed
    }

    /// 旧拼写 → 新拼写；`nil` 表示这个值不是需要翻译的修饰键。
    private static func renamedShortcutSpelling(_ stored: String) -> String? {
        switch stored {
        case "option": "alternate"
        case "disabled": "none"
        default: nil
        }
    }

    static var summonHoldDuration: Double {
        get {
            let value = defaults.object(forKey: "summonHoldDuration") as? Double ?? 150
            return min(max(value, 100), 300)
        }
        set {
            defaults.set(min(max(newValue, 100), 300), forKey: "summonHoldDuration")
        }
    }

    /// The modifier that summons the ring.
    ///
    /// `.none` is rejected on both sides: it exists for the optional
    /// clear-selection shortcut, and storing it here would leave Orbit with no
    /// way to be summoned at all.
    static var summonKey: ShortcutKey {
        get {
            guard let rawValue = defaults.string(forKey: "summonKey"),
                  let key = ShortcutKey(rawValue: rawValue),
                  key != .none else {
                return .alternate
            }
            return key
        }
        set {
            let safeValue = newValue == .none ? .alternate : newValue
            defaults.set(safeValue.rawValue, forKey: "summonKey")
        }
    }

    static var cardScale: CardScale {
        get {
            guard let rawValue = defaults.string(forKey: "cardScale"),
                  let size = CardScale(rawValue: rawValue) else {
                return .large
            }
            return size
        }
        set {
            defaults.set(newValue.rawValue, forKey: "cardScale")
        }
    }

    /// Optional key that clears a selection while the ring is open.
    static var clearSelectionKey: ShortcutKey {
        get {
            let stored = defaults.string(forKey: "clearSelectionModifier")
                .flatMap(ShortcutKey.init(rawValue:)) ?? .shift
            return stored == summonKey ? .none : stored
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

    /// 每次启动都先过一遍欢迎页。
    ///
    /// 默认开着，因为 Orbit 的整个交互就是「按住一个键不放」—— 屏幕上没有任何东西
    /// 能提示这件事，菜单栏图标也提示不了。只在第一次讲一遍的话，那一次没看清、
    /// 或者换了台机器，这个应用就等于没有入口了。
    ///
    /// 看够了的人在欢迎页上直接关掉它，之后再也不会出现；想找回来就在设置里。
    static var showWelcomeOnLaunch: Bool {
        get { defaults.object(forKey: "showWelcomeOnLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showWelcomeOnLaunch") }
    }

    /// 界面语言，`nil` 表示跟随系统。
    ///
    /// 真正起作用的是 `AppleLanguages`：CFBundle 在启动时读它来决定加载哪个
    /// `.lproj`，所以改完必须重启 Orbit 才生效。「系统设置 › 通用 › 语言与地区 ›
    /// 应用程序」写的也是这一个键，两边因此天然同步。
    ///
    /// 读的时候必须只看 Orbit 自己那份 plist。`UserDefaults.standard` 的搜索链里
    /// 包含 `NSGlobalDomain`，而那里一定有一个系统级的 `AppleLanguages` —— 用
    /// `defaults.array(forKey:)` 去读，会在用户从没选过语言的情况下读出系统语言，
    /// 于是下拉里显示的是某个具体语言而不是"跟随系统"。
    static var appLanguage: String? {
        get {
            guard let identifier = Bundle.main.bundleIdentifier,
                  let domain = defaults.persistentDomain(forName: identifier),
                  let languages = domain["AppleLanguages"] as? [String] else {
                return nil
            }
            return AppLanguage.normalize(languages.first)
        }
        set {
            if let newValue {
                defaults.set([newValue], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    static var ringOrder: RingOrder {
        get {
            guard let rawValue = defaults.string(forKey: "ringOrder"),
                  let order = RingOrder(rawValue: rawValue) else {
                return .recent
            }
            return order
        }
        set {
            defaults.set(newValue.rawValue, forKey: "ringOrder")
        }
    }

    /// Uses a new enum-backed key instead of migrating the old Boolean. That
    /// deliberately gives existing installs the new safe Cancel default once;
    /// users can then opt into the broader window-aware quick-switch behavior.
    static var ringOpeningBehavior: RingOpeningBehavior {
        get {
            guard let rawValue = defaults.string(forKey: "ringOpeningBehavior"),
                  let behavior = RingOpeningBehavior(rawValue: rawValue) else {
                return .cancel
            }
            return behavior
        }
        set {
            defaults.set(newValue.rawValue, forKey: "ringOpeningBehavior")
        }
    }

    /// 预览面板的缩放倍率。1.0 就是原本的尺寸。
    ///
    /// 放大不是简单地把上限调高：在常见屏幕上真正卡住卡片的不是
    /// `previewCardMaximumWidth`，而是"窗口的一半"。所以这个倍率同时参与决定
    /// 窗口该多宽 —— 见 `OrbitRingViewModel.previewDemand`。
    static var previewScale: CGFloat {
        get {
            let value = defaults.object(forKey: "previewScale") as? Double ?? 1
            return CGFloat(min(max(value, 0.7), 1.5))
        }
        set {
            defaults.set(Double(min(max(newValue, 0.7), 1.5)), forKey: "previewScale")
        }
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

    static var cardFinish: CardFinish {
        get {
            guard let rawValue = defaults.string(forKey: "cardFinish"),
                  let material = CardFinish(rawValue: rawValue) else {
                return .white
            }
            return material
        }
        set {
            defaults.set(newValue.rawValue, forKey: "cardFinish")
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

    /// 圆盘颜色来自哪里。
    ///
    /// Follow Accent is represented by the absence of a stored backdrop colour.
    /// That keeps existing installs on the old inherited behaviour and makes
    /// returning to the inherited value a real reset rather than a copied colour.
    static var ringBackdropMode: RingBackdropMode {
        get { hasCustomRingBackdropColor ? .custom : .followAccent }
        set {
            switch newValue {
            case .followAccent:
                defaults.removeObject(forKey: "ringBackdropColor")
            case .custom:
                // Capture the current accent when Custom is chosen for the first
                // time, so the visible colour does not jump during the switch.
                if !hasCustomRingBackdropColor {
                    setColor(accentColor, forKey: "ringBackdropColor")
                }
            }
        }
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
    private static var hasCustomRingBackdropColor: Bool {
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
