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

        // 跟 `windowCounts` 同一条规矩：标题这条判据只在真读得到标题时才收紧。
        return frontWindow(
            in: windows,
            ownedBy: pid,
            requiringTitle: CGPreflightScreenCaptureAccess()
        )
    }

    /// Whether one captured document surface is currently present on-screen.
    /// Fullscreen windows on other Spaces remain in the all-windows table but
    /// disappear from this one, making this a useful post-switch check.
    static func isWindowOnScreen(_ id: CGWindowID, ownedBy pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return contains(window: id, ownedBy: pid, in: windows)
    }

    /// 这次切换到底落在那扇窗上了没有。
    ///
    /// Every step of a switch reports only whether the *request* was accepted:
    /// an AX raise returns success for a window on another Space it never
    /// reached, and Chromium's AppleScript `set index` answers true after a
    /// reorder that crossed nothing. Asking the window server afterwards is the
    /// only answer that comes from where the user is actually looking, and it
    /// is what lets a failed step fall through to the next one instead of
    /// leaving the wrong window in front.
    ///
    /// - Returns: true when the switch landed — and also when the window server
    ///   declined to answer, because one failed query must not send an already
    ///   correct switch back through the fallback chain.
    static func switchLanded(on target: CGWindowID, ownedBy pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }

        return switchLanded(
            in: windows,
            on: target,
            ownedBy: pid,
            requiringTitle: CGPreflightScreenCaptureAccess()
        )
    }

    /// Pure form used by regression tests.
    ///
    /// 两种强度，跟这个文件里别处一样由权限决定用哪种。读得到标题时问的是最严的
    /// 那个问题——最前面的那扇是不是它——它能认出「切到了应用、但落在了另一扇窗」。
    /// 读不到标题时这个问题问不得：Chromium 的全屏窗口会把几扇无标题的容器面排在
    /// 页面前头，严判会把每一次正确的切换都判成失败，然后把整条降级链再跑一遍。
    /// 那时退到能问的那个问题：目标窗口在当前 Space 上露面了没有。
    static func switchLanded(
        in windows: [[String: Any]],
        on target: CGWindowID,
        ownedBy pid: pid_t,
        requiringTitle: Bool
    ) -> Bool {
        guard requiringTitle else {
            return contains(window: target, ownedBy: pid, in: windows)
        }
        return frontWindow(in: windows, ownedBy: pid, requiringTitle: true) == target
    }

    private static func contains(
        window id: CGWindowID,
        ownedBy pid: pid_t,
        in windows: [[String: Any]]
    ) -> Bool {
        windows.contains { window in
            window[kCGWindowOwnerPID as String] as? Int == Int(pid)
                && window[kCGWindowNumber as String] as? Int == Int(id)
        }
    }

    /// Picks the frontmost document surface from an already ordered window list.
    /// Chrome splits one fullscreen window into several normal-layer surfaces;
    /// its untitled toolbar/container can sit ahead of the titled page. Skipping
    /// that helper leaves the page itself as the answer.
    ///
    /// 这个答案不只是拿去在预览里藏一扇窗。它还是「当前应用要不要给一张卡」的
    /// 起点：认不出你正看着哪一扇，就算不出还有没有另一扇可切，那张卡也就不会
    /// 出现。所以 `requiringTitle` 必须由调用方按权限给 —— 没有屏幕录制权限时
    /// 标题一律是 nil，硬要求一个标题会把整条「切到同一应用的另一扇窗」的路
    /// 一起判死，而那正是这个版本的主功能。
    static func frontWindow(
        in windows: [[String: Any]],
        ownedBy pid: pid_t,
        requiringTitle: Bool
    ) -> CGWindowID? {
        for window in windows where window[kCGWindowOwnerPID as String] as? Int == Int(pid) {
            guard qualifiesAsWindow(window, requiringTitle: requiringTitle),
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

    /// The best window to switch to inside one app. Orbit's own per-app MRU
    /// history wins; the Window Server's existing front-to-back list is the
    /// stable fallback for windows not seen before.
    ///
    /// - Parameter currentWindowID: The window the user is looking at right
    ///   now, which must never be the answer — switching to it is a no-op.
    ///   `nil` when the app is not the one in front, where every window it owns
    ///   is a legitimate destination.
    /// - Parameter knownBlank: Windows a previous capture measured as drawing
    ///   nothing. 这一层只看得见层级、标题和尺寸，而空壳窗三样都齐全 —— 微信那扇
    ///   280x380 就是靠这条才不会成为松手时的落点。
    static func mostRecentOtherWindow(
        ownedBy pid: pid_t,
        excluding currentWindowID: CGWindowID?,
        preferredIDs: [CGWindowID],
        knownBlank: Set<CGWindowID> = []
    ) -> WindowTarget? {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return mostRecentOtherWindow(
            in: windows,
            ownedBy: pid,
            excluding: currentWindowID,
            preferredIDs: preferredIDs,
            requiringTitle: CGPreflightScreenCaptureAccess(),
            knownBlank: knownBlank
        )
    }

    /// Pure form used by regression tests. Input order is already Window Server
    /// front-to-back order, so it remains the tie-breaker after known MRU IDs.
    static func mostRecentOtherWindow(
        in windows: [[String: Any]],
        ownedBy pid: pid_t,
        excluding currentWindowID: CGWindowID?,
        preferredIDs: [CGWindowID],
        requiringTitle: Bool,
        knownBlank: Set<CGWindowID> = []
    ) -> WindowTarget? {
        let targets = windows.compactMap { window -> WindowTarget? in
            guard window[kCGWindowOwnerPID as String] as? Int == Int(pid),
                  let rawID = window[kCGWindowNumber as String] as? Int,
                  CGWindowID(rawID) != currentWindowID,
                  !knownBlank.contains(CGWindowID(rawID)),
                  qualifiesAsWindow(window, requiringTitle: requiringTitle),
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }

            // Without Screen Recording permission, cross-Space Chromium
            // windows have neither a usable title nor an AX window. They are
            // not actionable, so do not let one become a no-op first target.
            // An on-screen sibling can still be matched by frame through AX.
            if !requiringTitle,
               window[kCGWindowIsOnscreen as String] as? Bool != true {
                return nil
            }

            return WindowTarget(
                id: CGWindowID(rawID),
                title: window[kCGWindowName as String] as? String ?? "",
                frame: frame
            )
        }

        let preferredRank = Dictionary(
            uniqueKeysWithValues: preferredIDs.enumerated().map { ($0.element, $0.offset) }
        )
        return targets.enumerated().min { lhs, rhs in
            switch (preferredRank[lhs.element.id], preferredRank[rhs.element.id]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }?.element
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
        return bounds.width >= OrbitPreferences.minimumRealWindowSize.width
            && bounds.height >= OrbitPreferences.minimumRealWindowSize.height
    }

    /// 刻意跟 `qualifiesAsWindow` 用不同的尺寸下限，不是漏改。
    ///
    /// The two answer different questions. `qualifiesAsWindow` asks "is this
    /// worth a card and a thumbnail", so it holds out for a document-sized
    /// surface. This one backs `hasOnscreenWindow`, whose only caller decides
    /// whether an activated app needs its bundle reopened to get a window at
    /// all — there, *anything* the user can see is proof enough. Raising this
    /// floor to match would make Orbit open a second window behind every app
    /// whose only window happens to be small.
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
