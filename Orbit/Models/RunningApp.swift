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
    /// 「微信」答 W（经由拼音 *Wēixìn*），*Éditeur* 答 E，*1Password* 答 P。
    ///
    /// 逐个字符地问、问到就停，而不是把整个名字转写完再从结果里挑。名字里只要有
    /// 一个字符能折出拉丁字母，后面的字符就再也不影响答案，转写它们纯属浪费；而
    /// 中英混排的名字整串转写后，字符和原位置也不再一一对应。
    ///
    /// 一个字母都折不出来的名字（纯数字、纯符号、纯空白）没有字母快捷键 —— 宁可
    /// 没有，也好过认领一个错的。
    var letterShortcut: Character? {
        for character in name where !character.isWhitespace {
            if let letter = Self.latinInitial(of: character) {
                return letter
            }
        }
        return nil
    }

    /// 把单个字符折成一个大写 ASCII 字母；折不出来返回 `nil`。
    ///
    /// 两级：`folding` 先处理带变音符号和全角的拉丁字母（É → E，Ｓ → S），这一步
    /// 对汉字无能为力，所以剩下的交给 `.toLatin` 转写。转写只作用在这一个字符上，
    /// 代价是固定的。
    ///
    /// `isASCII` 这道关卡不能省：汉字本身的 `isLetter` 就是 `true`，光看
    /// `isLetter` 会让「微」原样过关，成为一个敲不出来的快捷键。
    private static func latinInitial(of character: Character) -> Character? {
        let source = String(character)

        if let direct = asciiLetter(in: source) {
            return direct
        }

        guard let transliterated = source.applyingTransform(.toLatin, reverse: false) else {
            return nil
        }
        return asciiLetter(in: transliterated)
    }

    private static func asciiLetter(in text: String) -> Character? {
        let folded = text.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        guard let initial = folded.uppercased().first, initial.isLetter, initial.isASCII else {
            return nil
        }
        return initial
    }
}

// MARK: - 激活

extension AppRecord {
    /// Bring the application to the foreground, reopening its bundle if needed.
    ///
    /// 分两级降级：先用 `NSRunningApplication` 直接激活；如果它成功了但应用一个
    /// 可见窗口都没有（Dock 里点一下才会重新开窗的那类应用），再用 `NSWorkspace`
    /// 重新 open 一次 bundle，等价于用户点 Dock 图标。
    /// - Parameter raisingAllWindows: Whether to restore the app's own
    ///   front-to-back window order along with it. Off when the caller has
    ///   already singled out a window, since bringing every window forward
    ///   would bury it again.
    /// - Returns: 是否已经发出了有效的激活请求。
    @discardableResult
    func bringToFront(raisingAllWindows: Bool = true) -> Bool {
        if let running = NSRunningApplication(processIdentifier: processIdentifier) {
            if running.isHidden {
                running.unhide()
            }

            let options: NSApplication.ActivationOptions = raisingAllWindows ? [.activateAllWindows] : []
            if running.activate(options: options) {
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
        gracePeriod: TimeInterval = OrbitPreferences.quitGracePeriod,
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
