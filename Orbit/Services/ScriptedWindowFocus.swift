//
//  ScriptedWindowFocus.swift
//  Orbit
//
//  Apple Events fallback for apps whose windows Accessibility cannot see.
//
//  Chromium-based apps (Chrome, Edge, Brave …) ship with their accessibility
//  tree switched off, so `AXWindows` on them is permanently empty and the AX
//  path in WindowPreviewService has nothing to raise. Chrome's *scripting*
//  interface, however, does list windows — and the window `name` it reports is
//  the active tab's title, which is exactly the string ScreenCaptureKit
//  captured. So for these apps the window is found again over Apple Events.
//
//  This costs one extra permission: the first use prompts the user with the
//  Automation dialog ("Orbit wants to control Google Chrome"). A decline makes
//  every later attempt fail fast, and the caller then falls back to plain
//  app activation — the behaviour Orbit always had.
//

import AppKit
import OSLog

private let scriptedWindowFocusLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.orbit.local",
    category: "WindowSwitch"
)

enum ScriptedWindowFocus {
    /// Asks the app itself, over Apple Events, to bring the window named
    /// `target.title` to the front.
    ///
    /// Runs off the main thread: a busy or hung target app answers Apple
    /// Events late, and Orbit's main thread also serves the event tap — a
    /// stall there stalls every keystroke on the system. The script carries
    /// its own 2-second timeout so an unresponsive app cannot pin the
    /// background worker for the default two minutes either.
    ///
    /// - Parameter completion: Called on the main queue with whether the app
    ///   reported a window switched. On false the caller should activate the
    ///   app the ordinary way.
    static func focus(
        _ target: WindowTarget,
        bundleIdentifier: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard !target.title.isEmpty, !bundleIdentifier.isEmpty else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let source = script(bundleIdentifier: bundleIdentifier, title: target.title)
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            // Apps without a scripting dictionary, a declined Automation
            // permission, and a title that matched nothing all land here the
            // same way: no `true` came back.
            let switched = result?.booleanValue == true
            DispatchQueue.main.async { completion(switched) }
        }
    }

    /// The AppleScript sent to the app. Matching mirrors
    /// `WindowPreviewService.titles(_:agreeWith:)`: exact or prefix in either
    /// direction, because the scripting `name` and the captured title come
    /// from different sides of the app and only agree up to decoration.
    static func script(bundleIdentifier: String, title: String) -> String {
        let escapedTitle = escaped(title)
        // Per-window `try`: asking `name of w` can throw on half-closed
        // windows, and one broken window must not abort the scan.
        return """
        set matchedWindow to missing value
        with timeout of 2 seconds
            tell application id "\(escaped(bundleIdentifier))"
                repeat with w in windows
                    try
                        set n to name of w
                        if (n is "\(escapedTitle)") or (n starts with "\(escapedTitle)") or ("\(escapedTitle)" starts with n) then
                            set matchedWindow to w
                            exit repeat
                        end if
                    end try
                end repeat
                if matchedWindow is not missing value then
                    try
                        set minimized of matchedWindow to false
                    end try
                    set index of matchedWindow to 1
                    activate
                end if
            end tell
        end timeout
        return matchedWindow is not missing value
        """
    }

    /// Escapes a string for use inside an AppleScript string literal.
    /// Backslashes first, then quotes — the reverse order would double-escape.
    static func escaped(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Window-menu fallback (Accessibility)

    /// Chromium implements AppleScript's `set index` as a bare reorder — no
    /// makeKey — so it cannot cross Spaces: a fullscreen window on another
    /// Space stays put, and the `activate` that follows lands on the app's
    /// *previous* Space. The one thing Chromium does expose over Accessibility
    /// is its menu bar, and each entry in the Window menu performs a real
    /// makeKeyAndOrderFront, exactly like clicking it — which is the primitive
    /// that carries a Space switch. Needs only the Accessibility permission
    /// Orbit already holds; no Automation prompt.
    ///
    /// - Parameter knownWindowTitles: Every real window title the app owns
    ///   right now (from the window server). Used to recognise the Window menu;
    ///   see `isWindowMenu`.
    static func focusViaWindowMenu(
        _ target: WindowTarget,
        pid: pid_t,
        knownWindowTitles: [String]
    ) -> Bool {
        // With a single window there is nothing to pick between, and plain
        // activation already follows it — while the menu heuristic below
        // genuinely needs two titles to be trustworthy.
        guard knownWindowTitles.count >= 2, !target.title.isEmpty else {
            scriptedWindowFocusLogger.notice(
                "menu precondition failed target=\(target.id, privacy: .public) known=\(knownWindowTitles.count, privacy: .public)"
            )
            return false
        }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.4)

        var value: AnyObject?
        let menuBarStatus = AXUIElementCopyAttributeValue(
            axApp,
            kAXMenuBarAttribute as CFString,
            &value
        )
        guard menuBarStatus == .success,
              let barRef = value, CFGetTypeID(barRef) == AXUIElementGetTypeID(),
              let topLevel = axChildren(of: barRef as! AXUIElement) else {
            scriptedWindowFocusLogger.notice(
                "menu bar unavailable target=\(target.id, privacy: .public) status=\(menuBarStatus.rawValue, privacy: .public)"
            )
            return false
        }

        // The Window menu sits near the right end of the bar, so walking
        // backwards finds it within a couple of menus instead of after
        // History's hundreds of rows.
        for barItem in topLevel.reversed() {
            guard let submenu = axChildren(of: barItem)?.first,
                  let items = axChildren(of: submenu) else { continue }

            let titles = items.map { axTitle(of: $0) ?? "" }
            guard isWindowMenu(itemTitles: titles, windowTitles: knownWindowTitles) else { continue }

            guard let index = titles.firstIndex(where: {
                WindowPreviewService.titles($0, agreeWith: target.title)
            }) else {
                scriptedWindowFocusLogger.notice(
                    "target absent from Window menu target=\(target.id, privacy: .public)"
                )
                return false
            }

            let targetItem = items[index]
            // AX timeouts are per element. Setting one on `axApp` does not
            // propagate to menu-item objects, so give the action itself enough
            // time to survive Chromium doing modal work in its callback.
            AXUIElementSetMessagingTimeout(targetItem, 1.0)
            let pressStatus = AXUIElementPerformAction(targetItem, kAXPressAction as CFString)
            scriptedWindowFocusLogger.notice(
                "Window menu press target=\(target.id, privacy: .public) status=\(pressStatus.rawValue, privacy: .public)"
            )
            return actionWasAccepted(pressStatus)
        }
        scriptedWindowFocusLogger.notice(
            "Window menu not recognised target=\(target.id, privacy: .public)"
        )
        return false
    }

    /// Apple documents `cannotComplete` as indeterminate rather than failed:
    /// an app doing modal work may time out after it already accepted the AX
    /// action. Falling through to AppleScript in that state immediately
    /// activates Chrome's old window and cancels a pending Space switch.
    static func actionWasAccepted(_ status: AXError) -> Bool {
        status == .success || status == .cannotComplete
    }

    /// The Window-menu press is enough when the selected window belongs to the
    /// app the user was already in. Reactivating that same process can restore
    /// its old key fullscreen window and cancel the cross-Space selection.
    /// A target app that was not frontmost still needs ordinary activation so
    /// macOS gives it focus after its Window-menu selection has registered.
    static func needsActivationAfterWindowMenu(
        targetProcess: pid_t,
        originatingFrontmostProcess: pid_t?
    ) -> Bool {
        targetProcess != originatingFrontmostProcess
    }

    /// Whether a menu is the app's Window menu, judged by its contents rather
    /// than its title — the title is localized to whatever language the app
    /// runs in. History or Bookmarks can echo *one* window's title (the page
    /// it came from), but only the Window menu lists them all; two distinct
    /// hits is the discriminator.
    static func isWindowMenu(itemTitles: [String], windowTitles: [String]) -> Bool {
        guard windowTitles.count >= 2 else { return false }
        let matched = Set(windowTitles).filter { windowTitle in
            itemTitles.contains { WindowPreviewService.titles($0, agreeWith: windowTitle) }
        }
        return matched.count >= 2
    }

    private static func axChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

}
