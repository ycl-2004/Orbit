//
//  AppListService.swift
//  Orbit
//

import AppKit
import Foundation

/// 收集当前值得放上环形界面的应用。
final class AppListService {
    static let shared = AppListService()

    /// Icons are re-fetched every time the ring opens, and `NSRunningApplication.icon`
    /// hits the bundle each call. Caching by bundle id keeps repeated summons cheap
    /// without holding the images alive once memory gets tight.
    private let iconCache = NSCache<NSString, NSImage>()

    private init() {
        iconCache.countLimit = 128
    }

    /// 列出当前正在运行、且值得显示的应用，按名称排序。
    ///
    /// - Important: 调用方应当在 Orbit 面板显示**之前**就取好前台应用的 pid 并传进来。
    ///   面板一旦显示，`NSWorkspace` 报告的前台应用就变成 Orbit 自己，而不是用户
    ///   原本在用的那个应用了。是否真的排除它，由这里判断。
    /// - Parameter frontmostProcessIdentifier: 唤出那一刻的前台进程。
    func getRunningApps(frontmostProcessIdentifier: pid_t? = nil) -> [AppInfo] {
        let workspace = NSWorkspace.shared

        // 整张窗口表每次调用都要复制一遍，所以一次唤出只问一次 —— 前台该不该排除，
        // 和哪些应用该上环，用的是同一份答案。
        //
        // Those two used to be separate queries with different options, which
        // also meant they could disagree: an app could be "windowed enough" to be
        // excluded as the frontmost one, yet not windowed enough to earn a card.
        let windowedPids = WindowVisibilityChecker.processesWithWindows()

        let listed = workspace.runningApplications
            .filter { shouldList($0, excluding: excluded(frontmostProcessIdentifier, windowedPids)) }

        // 兜底的触发条件是"问不出来"，不是"过滤结果为空"。
        //
        // Falling back on an empty result reads like the safer choice — a ring
        // with a few useless cards beats a ring with nothing on it — but it
        // inverts the setting exactly when the filter bites hardest: once the
        // survivors are all excluded for other reasons, every windowless app
        // comes straight back and the setting looks dead. An empty answer the
        // window server stands behind means the ring should be empty, and the hub
        // still cancels and still takes file drops.
        let survivors: [NSRunningApplication] = if OrbitConfig.hideWindowlessApps, let windowedPids {
            listed.filter { windowedPids.contains($0.processIdentifier) }
        } else {
            listed
        }

        let history = AppActivationHistory.shared
        let ranked = Self.byRecency(survivors.map(makeAppInfo), rank: history.rank(of:))

        // 名额和摆放是两件事。
        //
        // Which twelve get on the ring is always decided by recency — sorting by
        // name and then truncating is what let a first letter decide whether an
        // app could be switched to at all. How those twelve are then arranged is
        // a taste question the user answers in Settings.
        //
        // Orbit is a menu-bar app and intentionally does not pass the normal
        // activation-policy filter above, so it is added by hand and takes one of
        // the slots. It goes last whatever the order: its card is a cleanup
        // target, never the app you are switching to.
        let showsOrbit = OrbitConfig.showOrbitCard
        let slots = showsOrbit ? OrbitConfig.maxVisibleApps - 1 : OrbitConfig.maxVisibleApps
        let admitted = Array(ranked.prefix(max(slots, 0)))

        let ordered = switch OrbitConfig.ringOrder {
        case .recent: admitted
        case .alphabetical: admitted.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        }

        return showsOrbit ? ordered + [.orbit] : ordered
    }

    /// 环上最近用过的那个应用，也就是"按住、松开"该切过去的那个。
    ///
    /// 单独算而不是取列表第一个：按名字摆放时第一张卡跟最近使用没有关系。
    /// Orbit 自己的卡片永远不是答案 —— 它不是一个可以切过去的应用。
    static func mostRecent(among apps: [AppInfo], rank: (String) -> Int?) -> AppInfo? {
        apps
            .filter { !$0.isOrbit }
            .compactMap { app in rank(app.id).map { (app, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// 最近用过的排前面，从没见过的按名字排在它们后面。
    ///
    /// 环上只放得下 `maxVisibleApps` 张卡，所以这个顺序同时决定了"谁上得了环"。
    /// 按名字排再截断，等于让首字母决定一个应用能不能被切换到 —— 开着二十个应用
    /// 时，名字排在后面的那些永远够不着，界面上也没有任何地方说它们被藏了。
    ///
    /// `rank` 由调用方注入，既让这段排序能单独测，也让它不必知道历史是从哪来的。
    static func byRecency(_ apps: [AppInfo], rank: (String) -> Int?) -> [AppInfo] {
        apps.sorted { left, right in
            switch (rank(left.id), rank(right.id)) {
            case let (leftRank?, rightRank?):
                return leftRank < rightRank
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }

    /// 只有当前台应用确实有窗口时才把它排除掉。
    ///
    /// 否则从一个纯菜单栏应用唤出 Orbit 时，会白白少列一个本来该出现的应用。
    /// 问不出窗口状态时按"有窗口"处理：切回自己是白按一次，漏掉一个应用是少一条路。
    private func excluded(_ frontmost: pid_t?, _ windowedPids: Set<pid_t>?) -> pid_t? {
        guard let frontmost else { return nil }
        guard let windowedPids else { return frontmost }
        return windowedPids.contains(frontmost) ? frontmost : nil
    }

    private func shouldList(_ app: NSRunningApplication, excluding excludedPid: pid_t?) -> Bool {
        // 只要有 Dock 图标的普通应用；后台服务和辅助进程都跳过。
        guard app.activationPolicy == .regular else { return false }
        // Orbit 自己不出现在自己的环上。
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return app.processIdentifier != excludedPid
    }

    private func makeAppInfo(for app: NSRunningApplication) -> AppInfo {
        // pid 只是最后的兜底 key：它每次启动都会变，缓存也就不会命中，
        // 但至少不会让两个不同的应用共用同一个身份。
        let identity = app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)

        return AppInfo(
            id: identity,
            name: app.localizedName ?? NSLocalizedString("app.unnamed", comment: "Fallback app name"),
            icon: icon(for: app, cacheKey: identity),
            bundleURL: app.bundleURL,
            processIdentifier: app.processIdentifier
        )
    }

    private func icon(for app: NSRunningApplication, cacheKey: String) -> NSImage {
        let key = cacheKey as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }

        let icon = app.icon
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        iconCache.setObject(icon, forKey: key)
        return icon
    }
}
