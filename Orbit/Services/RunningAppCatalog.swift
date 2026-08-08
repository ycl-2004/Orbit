//
//  RunningAppCatalog.swift
//  Orbit
//

import AppKit
import Foundation

/// Supplies the application records shown by the ring.
final class RunningAppCatalog {
    static let shared = RunningAppCatalog()

    private let imageStore = NSCache<NSString, NSImage>()

    private init() {
        imageStore.countLimit = 128
    }

    /// Builds one snapshot for a summon. The frontmost process is captured by
    /// the window controller before its panel becomes the active application.
    func collect(frontmostProcess: pid_t? = nil) -> [AppRecord] {
        let workspace = NSWorkspace.shared
        let counts = WindowServerInspector.windowCounts()
        let owners = counts.map { Set($0.keys) }

        // 你此刻就在的那个应用从不参与常规排序 —— 它是最近用过的那个，留在里面
        // 会把「刚才那个应用」从第一张卡挤下去，而切回刚才那个才是最常做的事。
        var candidates = workspace.runningApplications.filter {
            isCandidate($0, excluding: frontmostProcess)
        }

        if OrbitConfig.hideWindowlessApps, let owners {
            candidates = candidates.filter { owners.contains($0.processIdentifier) }
        }

        // 它仍然可能拿到一张附加卡：见 `currentAppDeservesCard`。名额要先留出来，
        // 否则这张卡会把环撑过 `maxVisibleApps`。
        let currentCard = Self.currentAppDeservesCard(frontmostProcess, windowCounts: counts)
            ? frontmostProcess.flatMap(currentAppRecord)
            : nil

        let history = AppActivationHistory.shared
        let ranked = Self.orderedByUse(candidates.map(makeRecord), rank: history.rank(of:))
        let reserved = (OrbitConfig.showOrbitCard ? 1 : 0) + (currentCard == nil ? 0 : 1)
        let capacity = max(OrbitConfig.maxVisibleApps - reserved, 0)
        let selected = Array(ranked.prefix(capacity))

        let displayed: [AppRecord] = switch OrbitConfig.ringOrder {
        case .recent:
            selected
        case .alphabetical:
            selected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        // 两张特殊卡都挂在末尾，位置固定，不随排序方式跑动。
        return displayed + [currentCard].compactMap { $0 }
            + (OrbitConfig.showOrbitCard ? [.orbitCard] : [])
    }

    /// 你此刻就在的那个应用要不要给一张卡。
    ///
    /// 这张卡只有一个用途：切到这个应用的**别的**窗口。所以只有窗口不止一扇时
    /// 才给 —— 只有一扇的话，那扇就是你正看着的，卡片只会把你送回原地。
    ///
    /// 以前这里是「一律不给」，于是在 Chrome 上唤出 Orbit 时，Chrome 的其余窗口
    /// 一扇都够不着，哪怕预览面板明明能把它们全列出来。
    ///
    /// - Parameter windowCounts: `nil` 表示窗口服务没作答；答不上来就不给卡，
    ///   跟以前一样保守。
    static func currentAppDeservesCard(_ process: pid_t?, windowCounts: [pid_t: Int]?) -> Bool {
        guard let process, let windowCounts else { return false }
        return (windowCounts[process] ?? 0) > 1
    }

    private func currentAppRecord(_ process: pid_t) -> AppRecord? {
        guard let app = NSRunningApplication(processIdentifier: process),
              app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return makeRecord(from: app)
    }

    /// Returns the most recently activated switch target in a visible set.
    ///
    /// The frontmost app can still have a special card for reaching its other
    /// windows. That card is a manual destination, not the "previous app": if
    /// it participates here, its rank is necessarily first and summon/release
    /// simply lands back in the app the user is already viewing.
    static func mostRecentlyUsed(
        in apps: [AppRecord],
        excluding process: pid_t? = nil,
        rank: (String) -> Int?
    ) -> AppRecord? {
        apps
            .filter { !$0.isOrbit && (process == nil || $0.processIdentifier != process) }
            .compactMap { app in rank(app.id).map { (app, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Sorts known applications by their activation history, then falls back to
    /// a stable name comparison for records not present in that history.
    static func orderedByUse(_ apps: [AppRecord], rank: (String) -> Int?) -> [AppRecord] {
        apps.sorted { lhs, rhs in
            let leftRank = rank(lhs.id)
            let rightRank = rank(rhs.id)

            switch (leftRank, rightRank) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func isCandidate(_ app: NSRunningApplication, excluding process: pid_t?) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return app.processIdentifier != process
    }

    private func makeRecord(from app: NSRunningApplication) -> AppRecord {
        let identity = app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)
        return AppRecord(
            id: identity,
            name: app.localizedName ?? NSLocalizedString("app.unnamed", comment: "Fallback app name"),
            icon: image(for: app, identity: identity),
            bundleURL: app.bundleURL,
            processIdentifier: app.processIdentifier
        )
    }

    private func image(for app: NSRunningApplication, identity: String) -> NSImage {
        let key = identity as NSString
        if let image = imageStore.object(forKey: key) {
            return image
        }

        let image = app.icon
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        imageStore.setObject(image, forKey: key)
        return image
    }
}
