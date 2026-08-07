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
        let owners = WindowServerInspector.windowOwners()
        let excludedProcess = frontmostProcessToExclude(frontmostProcess, owners: owners)

        var candidates = workspace.runningApplications.filter {
            isCandidate($0, excluding: excludedProcess)
        }

        if OrbitConfig.hideWindowlessApps, let owners {
            candidates = candidates.filter { owners.contains($0.processIdentifier) }
        }

        let history = AppActivationHistory.shared
        let ranked = Self.orderedByUse(candidates.map(makeRecord), rank: history.rank(of:))
        let capacity = OrbitConfig.showOrbitCard
            ? max(OrbitConfig.maxVisibleApps - 1, 0)
            : OrbitConfig.maxVisibleApps
        let selected = Array(ranked.prefix(capacity))

        let displayed: [AppRecord] = switch OrbitConfig.ringOrder {
        case .recent:
            selected
        case .alphabetical:
            selected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        return OrbitConfig.showOrbitCard ? displayed + [.orbitCard] : displayed
    }

    /// Returns the most recently activated non-Orbit card in a visible set.
    static func mostRecentlyUsed(in apps: [AppRecord], rank: (String) -> Int?) -> AppRecord? {
        apps
            .filter { !$0.isOrbit }
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

    private func frontmostProcessToExclude(_ process: pid_t?, owners: Set<pid_t>?) -> pid_t? {
        guard let process else { return nil }
        guard let owners else { return process }
        return owners.contains(process) ? process : nil
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
