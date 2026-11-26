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

    /// 被单元测试当宿主拉起来的时候为真。
    ///
    /// The unit tests run inside Orbit itself. Without this, every test run
    /// installed the event tap, raised the welcome window and read and wrote
    /// the developer's own settings.
    static let isHostingUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// 系统设置里的「减弱动态效果」。
    ///
    /// 打开时环直接出现、直接消失，退出的卡片淡出而不碎开，星芯不再随选中鼓动。
    /// Views read the same setting through `\.accessibilityReduceMotion`; this
    /// is for the places that are not views.
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 被 UI 测试拉起来的时候为真：UI 测试启动 Orbit 时带上 `-OrbitUITesting`。
    ///
    /// The app boots for real — that is what the UI test checks — but raises no
    /// Accessibility prompt and no welcome window, and keeps its settings out of
    /// the developer's own.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-OrbitUITesting")

    /// 设置存放的域。测试时换成一个专用域，并在第一次用到时清空，每次都从默认值开始。
    static let storeName = isHostingUnitTests || isUITesting
        ? "app.orbit.local.tests"
        : (Bundle.main.bundleIdentifier ?? "app.orbit.local")

    /// Internal so the tests can pin and inspect raw values in the same store
    /// the app reads.
    static let store: UserDefaults = {
        guard isHostingUnitTests || isUITesting, let suite = UserDefaults(suiteName: storeName) else {
            return .standard
        }
        suite.removePersistentDomain(forName: storeName)
        return suite
    }()

    private static var defaults: UserDefaults { store }

    /// `defaults write app.orbit.local scrimStyle dusk|blurOnly|none`
    static var scrimStyle: ScrimStyle {
        choice("scrimStyle", default: .dusk)
    }

    /// 按 `rawValue` 存的枚举设置。没存过、或者存了一个认不得的值，都按默认值算。
    private static func choice<Value: RawRepresentable>(
        _ key: String,
        default fallback: Value
    ) -> Value where Value.RawValue == String {
        defaults.string(forKey: key).flatMap { Value(rawValue: $0) } ?? fallback
    }

    private static func setChoice<Value: RawRepresentable>(
        _ value: Value,
        forKey key: String
    ) where Value.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
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
            ("triggerModifier", "summonKey"),
        ] {
            defer { defaults.removeObject(forKey: legacyKey) }

            guard defaults.object(forKey: currentKey) == nil,
                  let legacyValue = defaults.object(forKey: legacyKey) else { continue }

            defaults.set(migratedValue(legacyValue), forKey: currentKey)
        }

        // 不再被读取的键：欢迎页「看过没有」由 `showWelcomeOnLaunch` 取代，
        // 「唤出时预选」由 `ringOpeningBehavior` 取代。
        for retiredKey in Self.retiredKeys {
            defaults.removeObject(forKey: retiredKey)
        }

        // 这个键名没变，但它存的是 `ShortcutKey.rawValue`，而那套拼写变了。
        if let stored = defaults.string(forKey: "clearSelectionModifier"),
           let renamed = renamedShortcutSpelling(stored) {
            defaults.set(renamed, forKey: "clearSelectionModifier")
        }
    }

    /// 以前写过、现在没有任何代码读的键。
    static let retiredKeys = ["hasSeenWelcome", "onboardingCompleted", "preselectRecentApp"]

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

    /// 长按多久唤出，单位毫秒。设置里的滑块用同一个范围。
    static let summonHoldRange: ClosedRange<Double> = 100 ... 300

    static var summonHoldDuration: Double {
        get {
            let value = defaults.object(forKey: "summonHoldDuration") as? Double ?? 150
            return summonHoldRange.clamping(value)
        }
        set {
            defaults.set(summonHoldRange.clamping(newValue), forKey: "summonHoldDuration")
        }
    }

    /// The modifier that summons the ring.
    ///
    /// `.none` is rejected on both sides: it exists for the optional
    /// clear-selection shortcut, and storing it here would leave Orbit with no
    /// way to be summoned at all.
    static var summonKey: ShortcutKey {
        get {
            let key = choice("summonKey", default: ShortcutKey.alternate)
            return key == .none ? .alternate : key
        }
        set {
            setChoice(newValue == .none ? .alternate : newValue, forKey: "summonKey")
        }
    }

    static var cardScale: CardScale {
        get { choice("cardScale", default: .large) }
        set { setChoice(newValue, forKey: "cardScale") }
    }

    /// Optional key that clears a selection while the ring is open.
    static var clearSelectionKey: ShortcutKey {
        get {
            let stored = choice("clearSelectionModifier", default: ShortcutKey.shift)
            return stored == summonKey ? .none : stored
        }
        set {
            setChoice(newValue, forKey: "clearSelectionModifier")
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
            guard let domain = defaults.persistentDomain(forName: storeName),
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
        get { choice("ringOrder", default: .recent) }
        set { setChoice(newValue, forKey: "ringOrder") }
    }

    /// Uses a new enum-backed key instead of migrating the old Boolean. That
    /// deliberately gives existing installs the new safe Cancel default once;
    /// users can then opt into the broader window-aware quick-switch behavior.
    static var ringOpeningBehavior: RingOpeningBehavior {
        get { choice("ringOpeningBehavior", default: .cancel) }
        set { setChoice(newValue, forKey: "ringOpeningBehavior") }
    }

    /// Whether the ring skips its initial fan-opening animation.
    ///
    /// The setting only changes how a summon is presented. It does not alter
    /// the hold threshold, selection animations, preview loading, or the
    /// collapse animation used when the ring is dismissed.
    static var instantRingOpening: Bool {
        get { defaults.object(forKey: "instantRingOpening") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "instantRingOpening") }
    }

    /// 预览面板的缩放倍率。1.0 就是原本的尺寸。
    ///
    /// 放大不是简单地把上限调高：在常见屏幕上真正卡住卡片的不是
    /// `previewCardMaximumWidth`，而是"窗口的一半"。所以这个倍率同时参与决定
    /// 窗口该多宽 —— 见 `OrbitRingViewModel.previewDemand`。
    /// 预览倍率的范围。设置里的滑块用同一个范围。
    static let previewScaleRange: ClosedRange<Double> = 0.7 ... 1.5

    static var previewScale: CGFloat {
        get {
            let value = defaults.object(forKey: "previewScale") as? Double ?? 1
            return CGFloat(previewScaleRange.clamping(value))
        }
        set {
            defaults.set(previewScaleRange.clamping(Double(newValue)), forKey: "previewScale")
        }
    }

    /// Opt-in because window capture needs the Screen Recording permission,
    /// which the ring itself does not.
    static var windowPreviewEnabled: Bool {
        get { defaults.bool(forKey: "windowPreviewEnabled") }
        set { defaults.set(newValue, forKey: "windowPreviewEnabled") }
    }

    static var ringPlacement: RingPlacement {
        get { choice("ringPlacement", default: .screenCenter) }
        set { setChoice(newValue, forKey: "ringPlacement") }
    }

    static var cardFinish: CardFinish {
        get { choice("cardFinish", default: .white) }
        set { setChoice(newValue, forKey: "cardFinish") }
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

    /// 解过的颜色，按存下来的那串字节记住。
    ///
    /// The colours are stored as keyed archives, and the ring reads them a few
    /// dozen times per redraw — every card's rim, the hub, the trail. Decoding
    /// each time was the bulk of that cost. Keying on the bytes rather than
    /// invalidating on write means a value changed anywhere, including with
    /// `defaults write`, is still picked up on the next read.
    private static var decodedColors: [String: (data: Data, color: Color)] = [:]

    private static func color(forKey key: String) -> Color? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let cached = decodedColors[key], cached.data == data {
            return cached.color
        }
        guard let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSColor.self,
            from: data
        ) else {
            return nil
        }
        let color = Color(nsColor: nsColor)
        decodedColors[key] = (data, color)
        return color
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
}

extension ClosedRange {
    /// 把一个值收进这个范围。
    func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
