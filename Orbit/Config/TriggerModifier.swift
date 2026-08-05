//
//  TriggerModifier.swift
//  Orbit
//

import AppKit

/// 可以用来唤出 Orbit 的修饰键。
///
/// Every case except `.disabled` maps onto exactly one `CGEventFlags` bit, so
/// the whole type is driven by a single lookup table instead of one switch per
/// property. `.disabled` is the odd one out: it maps to no bit at all, which is
/// what makes "no clear-selection key" expressible without a separate optional.
enum TriggerModifier: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift
    case disabled

    var id: String { rawValue }

    /// 所有真正对应一个修饰键的 case（即除 `.disabled` 外）。
    static var assignable: [TriggerModifier] {
        allCases.filter { $0.cgFlag.isEmpty == false }
    }

    /// 该修饰键涉及的全部 `CGEventFlags` 位，用于判断"是否只按了这一个键"。
    private static let modifierMask: CGEventFlags = [
        .maskAlternate, .maskCommand, .maskControl, .maskShift,
    ]

    /// 单个 case 的静态描述：事件位、键帽符号、本地化 key。
    private struct Descriptor {
        let flag: CGEventFlags
        let glyph: String
        let localizationKey: String
    }

    private var descriptor: Descriptor {
        switch self {
        case .option:
            Descriptor(flag: .maskAlternate, glyph: "⌥", localizationKey: "triggerKey.option")
        case .command:
            Descriptor(flag: .maskCommand, glyph: "⌘", localizationKey: "triggerKey.command")
        case .control:
            Descriptor(flag: .maskControl, glyph: "⌃", localizationKey: "triggerKey.control")
        case .shift:
            Descriptor(flag: .maskShift, glyph: "⇧", localizationKey: "triggerKey.shift")
        case .disabled:
            Descriptor(flag: [], glyph: "—", localizationKey: "triggerKey.disabled")
        }
    }

    var cgFlag: CGEventFlags { descriptor.flag }

    var symbol: String { descriptor.glyph }

    var localizedName: String {
        NSLocalizedString(descriptor.localizationKey, comment: "Modifier key name")
    }

    /// 该修饰键当前是否处于按下状态。
    ///
    /// `.disabled` 永远返回 `false`，因为它的掩码是空集，而 `contains([])` 恒为
    /// `true` —— 这里显式判空以避免那个陷阱。
    func isPressed(in flags: CGEventFlags) -> Bool {
        let flag = cgFlag
        guard !flag.isEmpty else { return false }
        return flags.contains(flag)
    }

    /// 除自己以外是否还按着别的修饰键。
    ///
    /// 用集合相减实现：把当前按下的四个修饰位里去掉自己，剩下任何一位都说明这是
    /// 一个组合键（例如 ⌥⇧Tab），此时不该把它当成 Orbit 的触发手势。
    func otherModifiersPressed(in flags: CGEventFlags) -> Bool {
        let flag = cgFlag
        guard !flag.isEmpty else { return false }
        return !flags.intersection(Self.modifierMask).subtracting(flag).isEmpty
    }
}
