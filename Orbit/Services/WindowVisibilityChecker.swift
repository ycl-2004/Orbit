//
//  WindowVisibilityChecker.swift
//  Orbit
//

import CoreGraphics

/// 判断某个进程当前是否真的有窗口摆在屏幕上。
///
/// `NSRunningApplication` alone cannot answer this: a menu-bar helper, an app
/// that has closed its last window, and an app sitting on another Space all look
/// identical from there. The window server, on the other hand, knows — so this
/// asks it directly and applies the three filters that separate a real document
/// window from the invisible bookkeeping windows every app keeps around.
enum WindowVisibilityChecker {
    /// 一个窗口要算作"用户看得见"必须同时满足的条件。
    private enum Threshold {
        /// 只认普通窗口层；菜单栏、Dock、悬浮面板都在非 0 层。
        static let normalLayer = 0
        /// 完全透明的窗口在屏幕上等于不存在。
        static let minimumAlpha = 0.01
        /// 1×1 之类的探针窗口不算真窗口。
        static let minimumEdge: CGFloat = 1
    }

    static func hasVisibleWindow(processIdentifier: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { window in
            isVisibleWindow(window, ownedBy: processIdentifier)
        }
    }

    /// 当前拥有窗口的所有进程。
    ///
    /// Deliberately drops `.optionOnScreenOnly`, which is the one thing that
    /// separates this from `hasVisibleWindow`: a minimized window, a window on
    /// another Space and a fullscreen app are all off-screen, and all three are
    /// things a person still wants to switch back to. What this answers is the
    /// narrower question "does anything at all belong to this app", so that an
    /// app with no windows whatsoever can be left off the ring.
    ///
    /// Returns the whole set in one pass because `CGWindowListCopyWindowInfo`
    /// copies the entire window table on every call — asking once per app would
    /// mean one full copy per card.
    ///
    /// - Returns: 有窗口的那些进程；`nil` 表示窗口服务没有作答 —— 调用方必须把它
    ///   和"谁都没有窗口"分开处理，否则一次查询失败会清空整个环。
    static func processesWithWindows() -> Set<pid_t>? {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // 标题是预览侧多出来的那一条过滤，而这里读不读得到取决于权限：没有屏幕录制
        // 权限时别的应用的 `kCGWindowName` 一律是 nil。每次唤出问一次 TCC，而不是
        // 每个窗口问一次，答案可用时才把判据收紧。
        let titlesReadable = CGPreflightScreenCaptureAccess()

        var pids: Set<pid_t> = []
        for window in windows where isRealWindow(window, requiringTitle: titlesReadable) {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int else { continue }
            pids.insert(pid_t(pid))
        }
        return pids
    }

    /// 一个窗口条目是不是「用户心里的那种窗口」。
    ///
    /// The window list is full of bookkeeping surfaces: autofill panels, menu
    /// shadows, 1×1 probes, fully transparent placeholders. Layer, alpha and
    /// size are what tell them apart from a document window.
    ///
    /// Size and layer cannot catch everything, though. Sequel Ace with its last
    /// window closed keeps a 500×500 untitled surface on layer 0 — the same shape
    /// loginwindow, Raycast and CC Switch all park there — and Terminal keeps a
    /// 260×330 one. Both clear every bar above and put a card on the ring whose
    /// preview then says "No windows to preview", because `WindowPreviewService`
    /// applies one filter more: a non-empty title.
    ///
    /// `requiringTitle` applies that same test. Callers pass true only when
    /// `CGPreflightScreenCaptureAccess()` says titles are readable — without that
    /// permission every title reads as nil, and requiring one would empty the ring.
    static func isRealWindow(_ window: [String: Any], requiringTitle: Bool = false) -> Bool {
        guard window[kCGWindowLayer as String] as? Int ?? 0 == Threshold.normalLayer else {
            return false
        }
        guard window[kCGWindowAlpha as String] as? Double ?? 1 > Threshold.minimumAlpha else {
            return false
        }
        if requiringTitle, (window[kCGWindowName as String] as? String ?? "").isEmpty {
            return false
        }
        guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return false
        }
        return bounds.width >= OrbitConfig.minimumRealWindowSize.width
            && bounds.height >= OrbitConfig.minimumRealWindowSize.height
    }

    private static func isVisibleWindow(_ window: [String: Any], ownedBy pid: pid_t) -> Bool {
        guard window[kCGWindowOwnerPID as String] as? Int == Int(pid) else {
            return false
        }
        guard window[kCGWindowLayer as String] as? Int ?? 0 == Threshold.normalLayer else {
            return false
        }
        guard window[kCGWindowAlpha as String] as? Double ?? 1 > Threshold.minimumAlpha else {
            return false
        }
        guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return false
        }
        return bounds.width > Threshold.minimumEdge && bounds.height > Threshold.minimumEdge
    }
}
