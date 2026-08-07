//
//  RunningApp.swift
//  Orbit
//

import AppKit
import Foundation

/// A running application as represented by one card in Orbit.
struct AppRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    let bundleURL: URL?
    let processIdentifier: pid_t
    let isOrbit: Bool

    init(
        id: String,
        name: String,
        icon: NSImage,
        bundleURL: URL?,
        processIdentifier: pid_t,
        isOrbit: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bundleURL = bundleURL
        self.processIdentifier = processIdentifier
        self.isOrbit = isOrbit
    }

    /// 两条记录指向同一个应用即视为相等；图标对象换了新实例不算变化。
    static func == (lhs: AppRecord, rhs: AppRecord) -> Bool {
        lhs.id == rhs.id
    }

    var isFinder: Bool {
        id == "com.apple.finder" || bundleURL?.lastPathComponent == "Finder.app"
    }
}

extension AppRecord {
    /// Orbit is a menu-bar app, so it has no regular document window to discover
    /// through `NSWorkspace`. It is still a real card in the ring, built from
    /// the app's own icon and process identity.
    static var orbitCard: AppRecord {
        AppRecord(
            id: Bundle.main.bundleIdentifier ?? "app.orbit",
            name: NSLocalizedString("app.orbit", comment: "Orbit app name"),
            icon: NSApp.applicationIconImage,
            bundleURL: Bundle.main.bundleURL,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            isOrbit: true
        )
    }
}

// MARK: - 键盘快捷键

extension AppRecord {
    /// The first Latin letter used by the optional name shortcut.
    ///
    /// The name is folded to Latin first, so 「微信」 answers to W (via *Wēixìn*)
    /// and *Éditeur* answers to E. Anything that still has no letter after
    /// folding — an app named only with digits or symbols — simply has no letter
    /// shortcut rather than claiming a wrong one.
    var letterShortcut: Character? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let latin = trimmed.applyingTransform(.toLatin, reverse: false) ?? trimmed
        let folded = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin

        guard let scalar = folded.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }
        return String(scalar).uppercased().first
    }
}

// MARK: - 激活

extension AppRecord {
    /// Bring the application to the foreground, reopening its bundle if needed.
    ///
    /// 分两级降级：先用 `NSRunningApplication` 直接激活；如果它成功了但应用一个
    /// 可见窗口都没有（Dock 里点一下才会重新开窗的那类应用），再用 `NSWorkspace`
    /// 重新 open 一次 bundle，等价于用户点 Dock 图标。
    /// - Returns: 是否已经发出了有效的激活请求。
    @discardableResult
    func bringToFront() -> Bool {
        if let running = NSRunningApplication(processIdentifier: processIdentifier) {
            if running.isHidden {
                running.unhide()
            }

            if running.activate(options: [.activateAllWindows]) {
                // 激活成功但没有窗口：让 bundle 自己重开一个。
                if !WindowServerInspector.hasOnscreenWindow(processIdentifier: processIdentifier) {
                    reopenBundle()
                }
                return true
            }
        }

        // 进程不在了，或激活被系统拒绝（常见于全屏 Space）：走 open bundle。
        return reopenBundle()
    }

    @discardableResult
    private func reopenBundle() -> Bool {
        guard let bundleURL else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hidesOthers = false

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Orbit: could not reopen %@ — %@", name, error.localizedDescription)
            }
        }
        return true
    }
}

// MARK: - 退出

extension AppRecord {
    /// Ask the application to quit and report whether it exited during the grace period.
    ///
    /// 只做礼貌退出，绝不 force kill。一个不肯退出的应用通常正卡在"有未保存的更改"
    /// 对话框上，强杀会直接丢掉用户的工作 —— 比留一张卡片在环上糟糕得多。这种情况
    /// 下这里只是报告"没退成"，由调用方原样保留该卡片。
    /// - Parameters:
    ///   - gracePeriod: 等待应用自行退出的秒数。
    ///   - completion: 回调参数为宽限期结束时该应用是否真的已经退出。
    func requestQuit(
        gracePeriod: TimeInterval = OrbitConfig.terminateGracePeriod,
        completion: @escaping (Bool) -> Void
    ) {
        guard let running = NSRunningApplication(processIdentifier: processIdentifier),
              running.terminate() else {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + gracePeriod) {
            completion(running.isTerminated)
        }
    }
}
