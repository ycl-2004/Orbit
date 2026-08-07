//
//  SettingsModel.swift
//  Orbit
//

import AppKit
import Combine
import SwiftUI

/// 设置窗口的可观察状态。
///
/// `OrbitConfig` is a plain `UserDefaults`-backed static store, so writing to it
/// never tells SwiftUI to redraw. This model is the bridge: every property
/// publishes for the UI and writes through to `OrbitConfig` in `didSet`, which
/// keeps the persistence rules in one place instead of spread across a dozen
/// `.onChange` handlers on the form.
@MainActor
final class SettingsModel: ObservableObject {
    /// 从 `OrbitConfig` 回填时置位，用来阻止 `didSet` 把刚读到的值又写回去。
    private var isReloading = false

    // MARK: - 触发

    @Published var longPressThreshold: Double = OrbitConfig.longPressThreshold {
        didSet { writeThrough { OrbitConfig.longPressThreshold = longPressThreshold } }
    }

    @Published var triggerModifier: TriggerModifier = OrbitConfig.triggerModifier {
        didSet {
            writeThrough {
                OrbitConfig.triggerModifier = triggerModifier
                // 把触发键设成原本的"取消选择键"会让后者自动失效，
                // 所以要把 OrbitConfig 消解后的结果读回来。
                syncing { clearSelectionModifier = OrbitConfig.clearSelectionModifier }
            }
        }
    }

    @Published var clearSelectionModifier: TriggerModifier = OrbitConfig.clearSelectionModifier {
        didSet { writeThrough { OrbitConfig.clearSelectionModifier = clearSelectionModifier } }
    }

    @Published var letterShortcutsEnabled: Bool = OrbitConfig.letterShortcutsEnabled {
        didSet { writeThrough { OrbitConfig.letterShortcutsEnabled = letterShortcutsEnabled } }
    }

    @Published var numericShortcutsEnabled: Bool = OrbitConfig.numericShortcutsEnabled {
        didSet { writeThrough { OrbitConfig.numericShortcutsEnabled = numericShortcutsEnabled } }
    }

    // MARK: - 外观

    @Published var ringPlacement: RingPlacement = OrbitConfig.ringPlacement {
        didSet { writeThrough { OrbitConfig.ringPlacement = ringPlacement } }
    }

    @Published var cardSize: CardSize = OrbitConfig.cardSize {
        didSet { writeThrough { OrbitConfig.cardSize = cardSize } }
    }

    @Published var cardMaterial: OrbitConfig.CardMaterial = OrbitConfig.cardMaterial {
        didSet { writeThrough { OrbitConfig.cardMaterial = cardMaterial } }
    }

    @Published var accentColor: Color = OrbitConfig.accentColor {
        didSet {
            writeThrough {
                OrbitConfig.accentColor = accentColor
                // 圆盘颜色没被单独设过时是跟着 accent 走的，所以要把它读回来，
                // 否则设置窗口里的色块会停在旧 accent 上，而圆环已经换色了。
                guard !OrbitConfig.hasCustomRingBackdropColor else { return }
                syncing { ringBackdropColor = OrbitConfig.ringBackdropColor }
            }
        }
    }

    @Published var ringBackdropEnabled: Bool = OrbitConfig.ringBackdropEnabled {
        didSet { writeThrough { OrbitConfig.ringBackdropEnabled = ringBackdropEnabled } }
    }

    @Published var ringBackdropColor: Color = OrbitConfig.ringBackdropColor {
        didSet { writeThrough { OrbitConfig.ringBackdropColor = ringBackdropColor } }
    }

    @Published var hideWindowlessApps: Bool = OrbitConfig.hideWindowlessApps {
        didSet { writeThrough { OrbitConfig.hideWindowlessApps = hideWindowlessApps } }
    }

    @Published var showOrbitCard: Bool = OrbitConfig.showOrbitCard {
        didSet { writeThrough { OrbitConfig.showOrbitCard = showOrbitCard } }
    }

    // MARK: - 窗口预览

    @Published var windowPreviewEnabled: Bool = OrbitConfig.windowPreviewEnabled {
        didSet {
            writeThrough {
                OrbitConfig.windowPreviewEnabled = windowPreviewEnabled
                // 第一次打开预览时才去要屏幕录制权限，而不是一启动就弹窗。
                guard windowPreviewEnabled, !hasScreenRecording else { return }
                WindowPreviewService.requestScreenRecordingPermission()
                syncing { hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission() }
            }
        }
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

    @Published private(set) var hasAccessibility = HotKeyService.checkAccessibilityPermission()
    @Published private(set) var hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission()

    /// 窗口出现时重新读一遍所有值。
    ///
    /// 权限可能在设置窗口关着的时候被用户改掉，配置也可能被另一个窗口改过。
    func reload() {
        syncing {
            longPressThreshold = OrbitConfig.longPressThreshold
            triggerModifier = OrbitConfig.triggerModifier
            clearSelectionModifier = OrbitConfig.clearSelectionModifier
            letterShortcutsEnabled = OrbitConfig.letterShortcutsEnabled
            numericShortcutsEnabled = OrbitConfig.numericShortcutsEnabled
            ringPlacement = OrbitConfig.ringPlacement
            cardSize = OrbitConfig.cardSize
            cardMaterial = OrbitConfig.cardMaterial
            accentColor = OrbitConfig.accentColor
            ringBackdropEnabled = OrbitConfig.ringBackdropEnabled
            ringBackdropColor = OrbitConfig.ringBackdropColor
            hideWindowlessApps = OrbitConfig.hideWindowlessApps
            showOrbitCard = OrbitConfig.showOrbitCard
            windowPreviewEnabled = OrbitConfig.windowPreviewEnabled
            launchAtLogin = LoginItemService.reload()
            hasAccessibility = HotKeyService.checkAccessibilityPermission()
            hasScreenRecording = WindowPreviewService.hasScreenRecordingPermission()
        }
    }

    /// 可以作为"取消选择键"的候选：不能跟触发键是同一个。
    var clearSelectionChoices: [TriggerModifier] {
        TriggerModifier.allCases.filter { $0 != triggerModifier }
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
