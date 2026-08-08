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
    func collect(
        frontmostProcess: pid_t? = nil,
        currentAppWindowTargetAvailable: Bool = true
    ) -> [AppRecord] {
        let workspace = NSWorkspace.shared
        let counts = WindowServerInspector.windowCounts()
        let owners = counts.map { Set($0.keys) }

        // 你此刻就在的那个应用不参与常规应用排序。它如果还有别的窗口，会在下面
        // 变成一个明确的“切到另一扇窗口”目标；否则把当前应用放进环只会送回原地。
        var candidates = workspace.runningApplications.filter {
            isCandidate($0, excluding: frontmostProcess)
        }

        if OrbitConfig.hideWindowlessApps, let owners {
            candidates = candidates.filter { owners.contains($0.processIdentifier) }
        }

        // 它仍然可能拿到一张窗口目标卡：见 `currentAppDeservesCard`。
        let currentCard = currentAppWindowTargetAvailable
            && Self.currentAppDeservesCard(frontmostProcess, windowCounts: counts)
            ? frontmostProcess.flatMap(currentAppRecord)
            : nil

        let history = AppActivationHistory.shared
        let ranked = Self.orderedByUse(candidates.map(makeRecord), rank: history.rank(of:))
        let switchTargetLimit = max(
            OrbitConfig.maxVisibleApps - (OrbitConfig.showOrbitCard ? 1 : 0),
            0
        )
        let displayed = Self.switchTargets(
            rankedApps: ranked,
            currentApp: currentCard,
            limit: switchTargetLimit,
            order: OrbitConfig.ringOrder
        )

        // Orbit 是清理工具，不是最近目标；它继续固定在序列末尾。
        return displayed
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

    /// Builds the actual keyboard sequence. If the frontmost app owns another
    /// real window, that window destination is more recent than leaving the app
    /// entirely, so its card owns the 12-o'clock anchor. Otherwise the previous
    /// application remains first. The cleanup card is deliberately handled by
    /// the caller and never enters this sequence.
    static func switchTargets(
        rankedApps: [AppRecord],
        currentApp: AppRecord?,
        limit: Int,
        order: RingOrder
    ) -> [AppRecord] {
        guard limit > 0 else { return [] }
        let recentTargets = Array(([currentApp].compactMap { $0 } + rankedApps).prefix(limit))
        return arranged(recentTargets, by: order)
    }

    /// Keeps the highest-priority switch destination as the stable first target
    /// in either mode. Alphabetical ordering begins after that anchor; otherwise
    /// the display preference would break the 12-o'clock muscle-memory contract.
    static func arranged(_ apps: [AppRecord], by order: RingOrder) -> [AppRecord] {
        guard let first = apps.first else { return [] }

        switch order {
        case .recent:
            return apps
        case .alphabetical:
            return [first] + apps.dropFirst().sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
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
