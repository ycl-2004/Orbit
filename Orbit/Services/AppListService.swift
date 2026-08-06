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
    ///   原本在用的那个应用了。
    /// - Parameter excludingProcessIdentifier: 要排除的进程（通常是当前前台应用）。
    func getRunningApps(excludingProcessIdentifier: pid_t? = nil) -> [AppInfo] {
        let workspace = NSWorkspace.shared
        let excludedPid = excludingProcessIdentifier ?? currentForegroundPid(in: workspace)

        let listed = workspace.runningApplications
            .filter { shouldList($0, excluding: excludedPid) }

        let survivors = OrbitConfig.hideWindowlessApps
            ? filterToWindowed(listed)
            : listed

        return survivors
            .map(makeAppInfo)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 把没有窗口的应用剔掉。
    ///
    /// 兜底的触发条件是"问不出来"，不是"过滤结果为空"。
    ///
    /// Falling back on an empty result reads like the safer choice — a ring with
    /// a few useless cards beats a ring with nothing on it — but it inverts the
    /// setting exactly when the filter bites hardest: once the survivors are all
    /// excluded for other reasons (the one windowed app being the frontmost one,
    /// say), every windowless app comes straight back and the setting looks dead.
    /// An empty answer the window server stands behind means the ring should be
    /// empty, and the hub still cancels and still takes file drops.
    private func filterToWindowed(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        // Read once, not once per app: every call copies the whole window table.
        guard let windowedPids = WindowVisibilityChecker.processesWithWindows() else {
            return apps
        }
        return apps.filter { windowedPids.contains($0.processIdentifier) }
    }

    /// 只有当前台应用确实有窗口时才把它排除掉。
    ///
    /// 否则从一个纯菜单栏应用唤出 Orbit 时，会白白少列一个本来该出现的应用。
    private func currentForegroundPid(in workspace: NSWorkspace) -> pid_t? {
        guard let frontmost = workspace.frontmostApplication else { return nil }
        let pid = frontmost.processIdentifier
        return WindowVisibilityChecker.hasVisibleWindow(processIdentifier: pid) ? pid : nil
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
