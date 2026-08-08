//
//  SettingsModel.swift
//  Orbit
//

import AppKit
import Combine
import SwiftUI

/// 设置窗口的可观察状态。
///
/// `OrbitPreferences` is a plain `UserDefaults`-backed static store, so writing to it
/// never tells SwiftUI to redraw. This model is the bridge: every property
/// publishes for the UI and writes through to `OrbitPreferences` in `didSet`, which
/// keeps the persistence rules in one place instead of spread across a dozen
/// `.onChange` handlers on the form.
@MainActor
final class SettingsModel: ObservableObject {
    /// 从 `OrbitPreferences` 回填时置位，用来阻止 `didSet` 把刚读到的值又写回去。
    private var isReloading = false

    // MARK: - 触发

    @Published var summonHoldDuration: Double = OrbitPreferences.summonHoldDuration {
        didSet { writeThrough { OrbitPreferences.summonHoldDuration = summonHoldDuration } }
    }

    @Published var summonKey: ShortcutKey = OrbitPreferences.summonKey {
        didSet {
            writeThrough {
                OrbitPreferences.summonKey = summonKey
                // 把触发键设成原本的"取消选择键"会让后者自动失效，
                // 所以要把 OrbitPreferences 消解后的结果读回来。
                syncing { clearSelectionKey = OrbitPreferences.clearSelectionKey }
            }
        }
    }

    @Published var clearSelectionKey: ShortcutKey = OrbitPreferences.clearSelectionKey {
        didSet { writeThrough { OrbitPreferences.clearSelectionKey = clearSelectionKey } }
    }

    @Published var letterShortcutsEnabled: Bool = OrbitPreferences.letterShortcutsEnabled {
        didSet { writeThrough { OrbitPreferences.letterShortcutsEnabled = letterShortcutsEnabled } }
    }

    @Published var numericShortcutsEnabled: Bool = OrbitPreferences.numericShortcutsEnabled {
        didSet { writeThrough { OrbitPreferences.numericShortcutsEnabled = numericShortcutsEnabled } }
    }

    // MARK: - 外观

    @Published var ringPlacement: RingPlacement = OrbitPreferences.ringPlacement {
        didSet { writeThrough { OrbitPreferences.ringPlacement = ringPlacement } }
    }

    @Published var cardScale: CardScale = OrbitPreferences.cardScale {
        didSet { writeThrough { OrbitPreferences.cardScale = cardScale } }
    }

    @Published var cardFinish: OrbitPreferences.CardFinish = OrbitPreferences.cardFinish {
        didSet { writeThrough { OrbitPreferences.cardFinish = cardFinish } }
    }

    @Published var accentColor: Color = OrbitPreferences.accentColor {
        didSet {
            writeThrough {
                OrbitPreferences.accentColor = accentColor
                // 圆盘颜色没被单独设过时是跟着 accent 走的，所以要把它读回来，
                // 否则设置窗口里的色块会停在旧 accent 上，而圆环已经换色了。
                guard !OrbitPreferences.hasCustomRingBackdropColor else { return }
                syncing { ringBackdropColor = OrbitPreferences.ringBackdropColor }
            }
        }
    }

    @Published var ringBackdropEnabled: Bool = OrbitPreferences.ringBackdropEnabled {
        didSet { writeThrough { OrbitPreferences.ringBackdropEnabled = ringBackdropEnabled } }
    }

    @Published var ringBackdropColor: Color = OrbitPreferences.ringBackdropColor {
        didSet { writeThrough { OrbitPreferences.ringBackdropColor = ringBackdropColor } }
    }

    @Published var hideWindowlessApps: Bool = OrbitPreferences.hideWindowlessApps {
        didSet { writeThrough { OrbitPreferences.hideWindowlessApps = hideWindowlessApps } }
    }

    @Published var showOrbitCard: Bool = OrbitPreferences.showOrbitCard {
        didSet { writeThrough { OrbitPreferences.showOrbitCard = showOrbitCard } }
    }

    // MARK: - 界面语言

    /// 这个模型被建出来那一刻的语言 —— 也就是设置窗口第一次被打开的时候。
    /// 重启提示要不要出现，比的是它。
    ///
    /// 之所以只能取到这个时刻而不是进程启动的时刻：CFBundle 在启动时就按
    /// `AppleLanguages` 选好了 `.lproj`，而设置窗口可能几个小时后才第一次打开。
    /// 两者之间只有一条路能改语言 —— 系统设置里的「语言与地区 › 应用程序」——
    /// 走那条路的人本来也会被系统提示重开应用。
    private let languageAtLaunch = OrbitPreferences.appLanguage

    /// `nil` = 跟随系统。
    @Published var appLanguage: String? = OrbitPreferences.appLanguage {
        didSet { writeThrough { OrbitPreferences.appLanguage = appLanguage } }
    }

    /// 语言换过了，但那次切换还没生效。
    ///
    /// 比的是"打开设置时是什么"而不是"上一次的值是什么"：来回切一圈又换回原样
    /// 的人不需要重启，此时再催他一次是在撒谎。
    var languageNeedsRestart: Bool {
        appLanguage != languageAtLaunch
    }

    /// 新实例没能起来，这一个就没有退。
    @Published private(set) var restartFailed = false

    /// 重开一个新实例，然后让这一个退出。
    ///
    /// 顺序不能反：先退出就没人负责把新的拉起来了。`.accessory` 应用没有窗口要
    /// 保存，重启对用户几乎无感 —— 这也是敢把语言做成应用内设置的前提。
    ///
    /// 但"重开"这一步是会失败的：Gatekeeper 拦下这份拷贝、磁盘映像被弹出、
    /// launch services 找不到 bundle，都会让回调带着 error 回来。以前无论回调
    /// 说什么都照样 `terminate`，于是一次失败的重启等于把 Orbit 关掉 —— 一个
    /// 菜单栏应用悄悄消失，用户既没换到新语言，也没有 Orbit 可用了。
    func restart() {
        restartFailed = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                guard error == nil, application != nil else {
                    self?.restartFailed = true
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Slider 要的是 Double，配置项存的是 CGFloat。
    @Published var previewScale: Double = Double(OrbitPreferences.previewScale) {
        didSet { writeThrough { OrbitPreferences.previewScale = CGFloat(previewScale) } }
    }

    @Published var ringOrder: RingOrder = OrbitPreferences.ringOrder {
        didSet { writeThrough { OrbitPreferences.ringOrder = ringOrder } }
    }

    @Published var ringOpeningBehavior: RingOpeningBehavior = OrbitPreferences.ringOpeningBehavior {
        didSet { writeThrough { OrbitPreferences.ringOpeningBehavior = ringOpeningBehavior } }
    }

    // MARK: - 窗口预览

    @Published var windowPreviewEnabled: Bool = OrbitPreferences.windowPreviewEnabled {
        didSet {
            writeThrough {
                OrbitPreferences.windowPreviewEnabled = windowPreviewEnabled
                // 第一次打开预览时才去要屏幕录制权限，而不是一启动就弹窗。
                guard windowPreviewEnabled, !hasScreenRecording else { return }
                WindowPreviewService.requestScreenRecordingPermission()
                syncing { hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission() }
            }
        }
    }

    // MARK: - 欢迎页

    @Published var showWelcomeOnLaunch: Bool = OrbitPreferences.showWelcomeOnLaunch {
        didSet { writeThrough { OrbitPreferences.showWelcomeOnLaunch = showWelcomeOnLaunch } }
    }

    // MARK: - 开机自启

    @Published var launchAtLogin: Bool = LoginItemService.isEnabled {
        didSet {
            writeThrough {
                do {
                    try LoginItemService.apply(enabled: launchAtLogin)
                } catch {
                    // launchd 拒绝了这次改动：把开关拨回它真实的状态。
                    syncing { launchAtLogin = LoginItemService.reload() }
                }
            }
        }
    }

    // MARK: - 只读的权限状态

    @Published private(set) var hasAccessibility = TriggerMonitor.accessibilityIsTrusted()
    @Published private(set) var hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission()

    /// 窗口出现时重新读一遍所有值。
    ///
    /// 权限可能在设置窗口关着的时候被用户改掉，配置也可能被另一个窗口改过。
    func reload() {
        syncing {
            summonHoldDuration = OrbitPreferences.summonHoldDuration
            summonKey = OrbitPreferences.summonKey
            clearSelectionKey = OrbitPreferences.clearSelectionKey
            letterShortcutsEnabled = OrbitPreferences.letterShortcutsEnabled
            numericShortcutsEnabled = OrbitPreferences.numericShortcutsEnabled
            appLanguage = OrbitPreferences.appLanguage
            ringPlacement = OrbitPreferences.ringPlacement
            cardScale = OrbitPreferences.cardScale
            cardFinish = OrbitPreferences.cardFinish
            accentColor = OrbitPreferences.accentColor
            ringBackdropEnabled = OrbitPreferences.ringBackdropEnabled
            ringBackdropColor = OrbitPreferences.ringBackdropColor
            hideWindowlessApps = OrbitPreferences.hideWindowlessApps
            showOrbitCard = OrbitPreferences.showOrbitCard
            ringOrder = OrbitPreferences.ringOrder
            previewScale = Double(OrbitPreferences.previewScale)
            ringOpeningBehavior = OrbitPreferences.ringOpeningBehavior
            windowPreviewEnabled = OrbitPreferences.windowPreviewEnabled
            launchAtLogin = LoginItemService.reload()
            hasAccessibility = TriggerMonitor.accessibilityIsTrusted()
            hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission()
        }
    }

    /// 可以作为"取消选择键"的候选：不能跟触发键是同一个。
    var clearSelectionChoices: [ShortcutKey] {
        ShortcutKey.allCases.filter { $0 != summonKey }
    }

    private func writeThrough(_ persist: () -> Void) {
        guard !isReloading else { return }
        persist()
    }

    private func syncing(_ body: () -> Void) {
        let wasReloading = isReloading
        isReloading = true
        body()
        isReloading = wasReloading
    }
}
