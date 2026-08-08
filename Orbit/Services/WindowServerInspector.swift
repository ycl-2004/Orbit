//
//  WindowServerInspector.swift
//  Orbit
//

import CoreGraphics

/// Queries the macOS window server for the surfaces that are useful to Orbit.
///
/// The running-application API cannot distinguish a menu-bar helper from an app
/// with a document window. This type keeps that policy in one place and exposes
/// both the per-process and whole-system queries needed by the ring.
enum WindowServerInspector {
    /// 一个窗口要算作"用户看得见"必须同时满足的条件。
    private enum Threshold {
        /// 只认普通窗口层；菜单栏、Dock、悬浮面板都在非 0 层。
        static let normalLayer = 0
        /// 完全透明的窗口在屏幕上等于不存在。
        static let minimumAlpha = 0.01
        /// 1×1 之类的探针窗口不算真窗口。
        static let minimumEdge: CGFloat = 1
    }

    static func hasOnscreenWindow(processIdentifier: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { window in
            isOnscreenEntry(window, owner: processIdentifier)
        }
    }

    /// 当前拥有窗口的所有进程。
    ///
    /// Deliberately drops `.optionOnScreenOnly`, which is the one thing that
    /// separates this from `hasOnscreenWindow`: a minimized window, a window on
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
    static func windowOwners() -> Set<pid_t>? {
        windowCounts().map { Set($0.keys) }
    }

    /// 每个进程各有多少扇真实窗口。
    ///
    /// 和 `windowOwners` 是同一次遍历的两种读法 —— 「有没有窗口」决定一个应用上
    /// 不上环，「有几扇」决定你此刻就在的那个应用还值不值得给一张卡。
    ///
    /// - Returns: `nil` 表示窗口服务没有作答，跟 `windowOwners` 一样必须和
    ///   「谁都没有窗口」分开处理。
    static func windowCounts() -> [pid_t: Int]? {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // 标题是预览侧多出来的那一条过滤，而这里读不读得到取决于权限：没有屏幕录制
        // 权限时别的应用的 `kCGWindowName` 一律是 nil。每次唤出问一次 TCC，而不是
        // 每个窗口问一次，答案可用时才把判据收紧。
        let titlesReadable = CGPreflightScreenCaptureAccess()

        var counts: [pid_t: Int] = [:]
        for window in windows where qualifiesAsWindow(window, requiringTitle: titlesReadable) {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int else { continue }
            counts[pid_t(pid), default: 0] += 1
        }
        return counts
    }

    /// 该进程在当前 Space 上最靠前的那扇真实窗口 —— 也就是用户此刻正看着的那扇。
    ///
    /// `.optionOnScreenOnly` 是按前到后返回的，所以第一个命中的就是最前面的。
    /// 走窗口服务而不是辅助功能，因为 Chromium 系应用对辅助功能一扇窗都不暴露，
    /// 而它们恰好是最需要这个答案的一类。
    static func frontWindow(ownedBy pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows where window[kCGWindowOwnerPID as String] as? Int == Int(pid) {
            guard qualifiesAsWindow(window),
                  let number = window[kCGWindowNumber as String] as? Int else { continue }
            return CGWindowID(number)
        }
        return nil
    }

    /// 属于该进程的真实窗口的标题，含别的 Space 上的和最小化的。
    ///
    /// 读别家应用的 `kCGWindowName` 需要屏幕录制权限；没有权限时标题全是
    /// nil，这里就返回空数组，调用方按「不知道」处理。
    static func windowTitles(ownedBy pid: pid_t) -> [String] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window in
            guard window[kCGWindowOwnerPID as String] as? Int == Int(pid),
                  qualifiesAsWindow(window, requiringTitle: true),
                  let name = window[kCGWindowName as String] as? String, !name.isEmpty else { return nil }
            return name
        }
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
    static func qualifiesAsWindow(_ window: [String: Any], requiringTitle: Bool = false) -> Bool {
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

    private static func isOnscreenEntry(_ window: [String: Any], owner pid: pid_t) -> Bool {
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
