//
//  HotKeyService.swift
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

    let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let shouldConsumeKeyDown = type == .keyDown && service.orbitIsOpen

    DispatchQueue.main.async {
        switch type {
        case .flagsChanged:
            service.handleFlagsChanged(flags)
        case .keyDown:
            service.handleKeyDown(keyCode: keyCode)
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

final class HotKeyService {
    static let shared = HotKeyService()

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

        let modifier = OrbitConfig.triggerModifier
        guard modifier != .disabled else { return false }
        return modifier.isPressed(in: CGEventSource.flagsState(.combinedSessionState))
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
        let modifier = OrbitConfig.clearSelectionModifier
        guard modifier != .disabled else { return nil }
        return modifier.cgFlag
    }

    private init() {}

    static func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func startListening() {
        guard !listening else { return }
        guard Self.checkAccessibilityPermission() else { return }

        let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let mask = flagsChangedMask | keyDownMask

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

    func stopListening() {
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
        let modifier = OrbitConfig.triggerModifier
        guard modifier != .disabled else { return }

        // Track the clear key on its own edge, so holding it down does not
        // fire repeatedly and releasing it does nothing.
        let clearDown = clearSelectionFlag.map(flags.contains) ?? false
        if orbitHasOpened, clearDown, !clearKeyPressed {
            post(.deselect)
        }
        clearKeyPressed = clearDown

        let pressed = modifier.isPressed(in: flags)
        if pressed && modifier.otherModifiersPressed(in: flags) {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + OrbitConfig.longPressThreshold / 1_000) { [weak self] in
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

    fileprivate func handleKeyDown(keyCode: Int64) {
        guard orbitHasOpened else { return }

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
            guard OrbitConfig.numericShortcutsEnabled else { return }
            post(.number, value: number(for: keyCode))
        default:
            guard OrbitConfig.letterShortcutsEnabled,
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
