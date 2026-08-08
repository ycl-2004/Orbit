//
//  TriggerMonitor.swift
//  Orbit
//
//  Watches modifier and keyboard events so Orbit can be summoned without
//  taking over a permanent global shortcut.
//

import ApplicationServices
import AppKit
import CoreGraphics

private func orbitEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<TriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let shouldConsumeKeyDown = type == .keyDown && service.orbitIsOpen

    DispatchQueue.main.async {
        switch type {
        case .flagsChanged:
            service.handleFlagsChanged(flags)
        case .keyDown:
            service.handleKeyDown(keyCode: keyCode)
        // 按住触发键的同时点鼠标或滚滚轮 —— ⌥ 拖拽复制、⌥ 点下载、⌥ 滚动缩放 ——
        // 说明这一次按住是别的手势的一部分，不是在召唤 Orbit。
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            service.abandonPendingSummon()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = service.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        default:
            break
        }
    }

    // An active tap can discard navigation keys after Orbit is visible. This
    // keeps Tab/arrows/number/letter commands from also reaching the app that
    // was active underneath the ring.
    return shouldConsumeKeyDown ? nil : Unmanaged.passUnretained(event)
}

final class TriggerMonitor {
    static let shared = TriggerMonitor()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var listening = false
    private var triggerPressed = false
    private var orbitHasOpened = false
    private var pressToken = UUID()
    private var clearKeyPressed = false

    /// Gates key swallowing. Deliberately checks the *live* modifier state
    /// rather than trusting `orbitHasOpened` alone: if a release event is ever
    /// missed — lock screen, Mission Control, fast user switching — that flag
    /// stays true and the tap would silently eat every keystroke on the
    /// system, with no ring on screen to explain why.
    fileprivate var orbitIsOpen: Bool {
        guard orbitHasOpened else { return false }

        let key = OrbitPreferences.summonKey
        guard key != .none else { return false }
        return key.isDown(in: CGEventSource.flagsState(.combinedSessionState))
    }

    /// The ring can close without the trigger being released — Escape, a
    /// click on the hub, activating an app. Keys must stop being swallowed at
    /// that moment, not whenever the modifier happens to come up.
    func orbitDidClose() {
        orbitHasOpened = false
        clearKeyPressed = false
    }

    /// Tapped while the ring is open, this clears the current selection.
    /// `nil` when the user has turned the shortcut off.
    private var clearSelectionFlag: CGEventFlags? {
        let key = OrbitPreferences.clearSelectionKey
        guard key != .none else { return nil }
        return key.eventFlags
    }

    private init() {}

    static func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func beginMonitoring() {
        guard !listening else { return }
        guard Self.accessibilityIsTrusted() else { return }

        // 鼠标和滚轮只用来"撤销一次待发的召唤"，从不被吞掉。刻意不订阅
        // mouseMoved/mouseDragged：按住 ⌥ 光是移动鼠标仍然是一次合法的召唤，
        // 而且那两个事件每秒上百次，白白让每一次都过一遍 tap。
        let types: [CGEventType] = [
            .flagsChanged, .keyDown,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: orbitEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            return
        }

        eventTap = tap
        runLoopSource = source
        listening = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func endMonitoring() {
        cancelPendingPress()
        triggerPressed = false
        orbitHasOpened = false
        clearKeyPressed = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        runLoopSource = nil
        eventTap = nil
        listening = false
    }

    fileprivate func handleFlagsChanged(_ flags: CGEventFlags) {
        let key = OrbitPreferences.summonKey
        guard key != .none else { return }

        // Track the clear key on its own edge, so holding it down does not
        // fire repeatedly and releasing it does nothing.
        let clearDown = clearSelectionFlag.map(flags.contains) ?? false
        if orbitHasOpened, clearDown, !clearKeyPressed {
            post(.deselect)
        }
        clearKeyPressed = clearDown

        let pressed = key.isDown(in: flags)
        if pressed && key.conflictsWithAnotherModifier(in: flags) {
            // Once the ring is up a second modifier is a command, not a
            // reason to abandon the trigger — abandoning it here used to
            // leave the ring stranded on screen after the trigger released.
            guard !orbitHasOpened else { return }
            triggerPressed = false
            cancelPendingPress()
            return
        }

        if pressed {
            guard !triggerPressed else { return }
            triggerPressed = true
            let token = UUID()
            pressToken = token

            DispatchQueue.main.asyncAfter(deadline: .now() + OrbitPreferences.summonHoldDuration / 1_000) { [weak self] in
                guard let self,
                      self.triggerPressed,
                      self.pressToken == token,
                      !self.orbitHasOpened else { return }

                self.orbitHasOpened = true
                NotificationCenter.default.post(
                    name: .orbitSummonRequested,
                    object: NSValue(point: NSEvent.mouseLocation)
                )
            }
        } else if triggerPressed {
            triggerPressed = false
            cancelPendingPress()

            if orbitHasOpened {
                orbitHasOpened = false
                NotificationCenter.default.post(name: .orbitTriggerReleased, object: nil)
            }
        }
    }

    /// 按住触发键期间碰了别的输入，就把这次待发的召唤作废。
    ///
    /// ⌥ 长按 150ms 无条件唤出，是 Orbit 最容易被误触发的地方：⌥+←/→ 按词移动
    /// 光标、⌥+delete 删词、⌥ 拖拽复制文件，全都要按住 ⌥ 远超 150ms。以前只有
    /// "松开触发键"和"按下第二个修饰键"能撤销计时器，普通按键根本不参与判定，
    /// 于是圆环会在打字打到一半时跳出来，并从那一刻起开始吞掉后面每一次按键。
    ///
    /// 作废之后要重新按一次触发键才能召唤，这跟所有长按手势的约定一致。已经开着
    /// 的环不受影响 —— 那时候按键是命令，不是打字。
    fileprivate func abandonPendingSummon() {
        guard !orbitHasOpened, triggerPressed else { return }
        triggerPressed = false
        cancelPendingPress()
    }

    fileprivate func handleKeyDown(keyCode: Int64) {
        guard orbitHasOpened else {
            abandonPendingSummon()
            return
        }

        switch keyCode {
        case 53:
            post(.cancel)
        case 36, 76:
            post(.activate)
        case 48, 125:
            post(.next)
        case 126:
            post(.previous)
        // Left/right step through the selected app's windows; the ring itself
        // stays on up/down so the two axes never fight.
        case 124:
            post(.nextWindow)
        case 123:
            post(.previousWindow)
        case 18, 19, 20, 21, 23, 22, 26, 28, 25:
            guard OrbitPreferences.numericShortcutsEnabled else { return }
            post(.number, value: number(for: keyCode))
        default:
            guard OrbitPreferences.letterShortcutsEnabled,
                  let letter = letter(for: keyCode) else { return }
            post(.letter, value: letter)
        }
    }

    private func post(_ command: OrbitKeyboardCommand, value: String? = nil) {
        var userInfo: [AnyHashable: Any] = ["command": command.rawValue]
        if let value {
            userInfo["value"] = value
        }
        NotificationCenter.default.post(name: .orbitKeyboardCommand, object: nil, userInfo: userInfo)
    }

    private func cancelPendingPress() {
        pressToken = UUID()
    }

    private func number(for keyCode: Int64) -> String {
        [18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"][keyCode] ?? ""
    }

    private func letter(for keyCode: Int64) -> String? {
        [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
            34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
        ][keyCode]
    }
}
