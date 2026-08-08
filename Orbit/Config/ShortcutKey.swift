//
//  ShortcutKey.swift
//  Orbit
//

import AppKit

/// User-selectable modifier keys used by the summon and clear-selection gestures.
///
/// `rawValue` is written straight to `UserDefaults`, so the spellings here are a
/// storage format rather than display text — `localizedTitle` is what the
/// settings window shows.
enum ShortcutKey: CaseIterable, Identifiable, Equatable {
    case alternate
    case command
    case control
    case shift
    case none

    static var allCases: [ShortcutKey] { [.alternate, .command, .control, .shift, .none] }

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .alternate: "alternate"
        case .command: "command"
        case .control: "control"
        case .shift: "shift"
        case .none: "none"
        }
    }

    nonisolated init?(rawValue: String) {
        switch rawValue {
        case "alternate": self = .alternate
        case "command": self = .command
        case "control": self = .control
        case "shift": self = .shift
        case "none": self = .none
        default: return nil
        }
    }

    /// Keys that can actually summon Orbit. `.none` is only for the optional
    /// clear-selection shortcut.
    static var usableForSummon: [ShortcutKey] {
        allCases.filter { $0 != .none }
    }

    private var flag: CGEventFlags {
        switch self {
        case .alternate: .maskAlternate
        case .command: .maskCommand
        case .control: .maskControl
        case .shift: .maskShift
        case .none: []
        }
    }

    var eventFlags: CGEventFlags { flag }

    var glyph: String {
        switch self {
        case .alternate: "⌥"
        case .command: "⌘"
        case .control: "⌃"
        case .shift: "⇧"
        case .none: "—"
        }
    }

    var localizedTitle: String {
        let key = switch self {
        case .alternate: "triggerKey.option"
        case .command: "triggerKey.command"
        case .control: "triggerKey.control"
        case .shift: "triggerKey.shift"
        case .none: "triggerKey.disabled"
        }
        return NSLocalizedString(key, comment: "Shortcut key name")
    }

    func isDown(in flags: CGEventFlags) -> Bool {
        self != .none && flags.contains(flag)
    }

    func conflictsWithAnotherModifier(in flags: CGEventFlags) -> Bool {
        guard self != .none else { return false }

        let pressed: [(ShortcutKey, Bool)] = [
            (.alternate, flags.contains(.maskAlternate)),
            (.command, flags.contains(.maskCommand)),
            (.control, flags.contains(.maskControl)),
            (.shift, flags.contains(.maskShift)),
        ]
        return pressed.contains { key, isPressed in key != self && isPressed }
    }
}
