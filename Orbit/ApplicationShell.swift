//
//  ApplicationShell.swift
//  Orbit
//

import AppKit
import ApplicationServices
import SwiftUI

@main
struct OrbitApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate

    var body: some Scene {
        // Orbit 的实际界面全部由 AppDelegate 用 AppKit 窗口驱动。这里保留一个
        // Settings 场景，只是为了让系统的「设置…」菜单项和 ⌘, 有地方可去。
        Settings {
            SettingsView()
        }
        .defaultSize(width: SettingsView.preferredSize.width, height: SettingsView.preferredSize.height)
    }
}

/// 菜单栏常驻应用的生命周期。
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var summonObserver: NSObjectProtocol?

    /// 首次运行后写入的标记；改成 `true` 可以在调试时强制重看欢迎页。
    private static let alwaysShowWelcome = false
    private static let welcomeSeenKey = "onboardingCompleted"

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 必须排在最前：后面每一步都会读设置，而升级上来的机器此刻还只有旧键。
        OrbitPreferences.migrateStoredPreferences()

        // 不占 Dock 图标，只在菜单栏出现。
        NSApp.setActivationPolicy(.accessory)

        Self.boundAccessibilityMessaging()
        installStatusItem()
        // 越早开始记越好：环上放得下哪些应用，取决于这份历史有多长。
        AppActivationHistory.shared.start()
        observeSummonRequests()
        resumeEventTapIfPermitted()
        presentWelcomeIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 用户可能刚在"系统设置"里授予了辅助功能权限。回到前台时重试一次，
        // 这样不用重启 Orbit 快捷键就能生效。
        resumeEventTapIfPermitted()
        // 屏幕录制也可能是刚给的 —— 给完角标就该自己消失。
        refreshStatusItemAppearance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let summonObserver {
            NotificationCenter.default.removeObserver(summonObserver)
        }
        TriggerMonitor.shared.endMonitoring()
    }

    /// 给这个进程发出的每一次辅助功能往返设一个统一的上限。
    ///
    /// `AXUIElementSetMessagingTimeout` is documented as per-object: a timeout
    /// set on an application element covers messages to that element and
    /// nothing else. So the 0.4 s guards inside `WindowPreviewService` and
    /// `ScriptedWindowFocus` only ever protected the first hop — the window,
    /// menu and menu-item objects those two then walk kept the framework
    /// default of several seconds each.
    ///
    /// 这件事要紧，是因为那些遍历跑在主线程上，而事件 tap 的回调也在那条线上：
    /// 主线程停一拍，全系统的键盘输入就跟着停一拍。而"目标应用正卡着"恰恰是
    /// 用户最想按切换器的时刻。宁可放弃一次切换，也不能卡住别人的键盘。
    ///
    /// Passing the system-wide object is what makes this global; individual
    /// elements can still ask for more, and the Window-menu press does.
    private static func boundAccessibilityMessaging() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.4)
    }

    /// 只有拿到辅助功能权限时才装事件监听；没权限时反复调用也无副作用。
    private func resumeEventTapIfPermitted() {
        guard TriggerMonitor.accessibilityIsTrusted() else { return }
        TriggerMonitor.shared.beginMonitoring()
    }

    private func presentWelcomeIfNeeded() {
        guard Self.alwaysShowWelcome || OrbitPreferences.showWelcomeOnLaunch else { return }

        // 稍等一拍再弹，让菜单栏图标和事件监听先就位，
        // 否则欢迎窗口可能抢在应用真正激活之前出现。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            OnboardingWindowController.shared.show()
            UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
        }
    }

    // MARK: - 唤出环形界面

    private func observeSummonRequests() {
        summonObserver = NotificationCenter.default.addObserver(
            forName: .orbitSummonRequested,
            object: nil,
            queue: .main
        ) { notification in
            let anchor = (notification.object as? NSValue)?.pointValue ?? NSEvent.mouseLocation
            Task { @MainActor in
                OrbitWindowController.shared.show(at: anchor)
            }
        }
    }

    // MARK: - 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemPressed)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshStatusItemAppearance()
    }

    /// 权限齐全时这里什么也不画，菜单栏和以前一模一样；只有预览真的用不了时才
    /// 补上角标。图标是菜单栏上唯一持续可见的表面，而预览失效恰恰是安静的，
    /// 不在这里说一声就没有别的地方能说了。
    private func refreshStatusItemAppearance() {
        statusItem?.button?.image = Self.statusItemImage(
            needsAttention: WindowPreviewService.windowPreviewNeedsAuthorization
        )
    }

    /// 菜单栏图标：环 + 中心球，取自 app 图标的骨架。
    ///
    /// Template rendering is what makes it work in the menu bar: macOS throws the
    /// color away and keeps only the alpha, so the same asset inverts for a dark
    /// menu bar and tints while the menu is open. The system symbol behind it is
    /// insurance — a status item with no image is an invisible button, which
    /// would leave the menu unreachable.
    private static func statusItemImage(needsAttention: Bool = false) -> NSImage? {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "Orbit"

        guard needsAttention, let image else { return image }
        return badged(image)
    }

    /// 在图标右上角点一个角标。
    ///
    /// 先用 `destinationOut` 挖掉一个大一圈的洞再填实心点：模板图像里所有像素都是
    /// 同一个颜色，不挖这个洞，角标就和环糊成一块，看着只是图标变形了。
    private static func badged(_ base: NSImage) -> NSImage {
        let badge = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            guard let context = NSGraphicsContext.current else { return true }

            let clearing = NSRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 8, height: 8)
            context.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: clearing).fill()

            context.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: clearing.insetBy(dx: 1.6, dy: 1.6)).fill()
            return true
        }
        badge.isTemplate = true
        badge.accessibilityDescription = NSLocalizedString(
            "statusMenu.preview.missing",
            comment: "Menu bar icon state when window previews lost access"
        )
        return badge
    }

    /// 左键和右键都弹同一个菜单 —— Orbit 没有"点一下就执行"的主操作，
    /// 让两个键行为不同只会让人猜。
    @objc private func statusItemPressed() {
        // 顺手重试一次授权：用户往往是刚授完权就来点菜单栏图标的。
        resumeEventTapIfPermitted()
        refreshStatusItemAppearance()
        popUpMenu(buildMenu())
    }

    private func buildMenu() -> NSMenu {
        let isAuthorized = TriggerMonitor.accessibilityIsTrusted()
        let previewNeedsAccess = WindowPreviewService.windowPreviewNeedsAuthorization
        let menu = NSMenu()

        menu.addItem(infoItem(
            isAuthorized ? "statusMenu.permission.granted" : "statusMenu.permission.missing"
        ))
        // 只在预览真的用不了时才多这一行。权限齐全的人看到的菜单和以前一模一样。
        if previewNeedsAccess {
            menu.addItem(infoItem("statusMenu.preview.missing"))
        }
        menu.addItem(infoItem(String(
            format: NSLocalizedString("statusMenu.hint.hold", comment: "How to summon Orbit"),
            OrbitPreferences.summonKey.glyph
        )))
        menu.addItem(.separator())

        if !isAuthorized {
            menu.addItem(actionItem("statusMenu.grantAccess", #selector(revealAccessibilitySettings)))
        }
        if previewNeedsAccess {
            menu.addItem(actionItem(
                "statusMenu.grantScreenRecording",
                #selector(revealScreenRecordingSettings)
            ))
        }
        menu.addItem(actionItem("statusMenu.preferences", #selector(revealSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("statusMenu.quit", #selector(quitOrbit), key: "q"))

        return menu
    }

    /// 只用来显示信息、不可点击的菜单项。
    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ titleKey: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString(titleKey, comment: ""),
            action: action,
            keyEquivalent: key
        )
        item.target = self
        return item
    }

    /// 把菜单临时挂到 status item 上弹出，弹完立刻摘掉。
    ///
    /// 一直挂着菜单的话，`button.action` 就永远收不到点击事件了 —— 而我们需要那次
    /// 点击来重试权限、并按当前权限状态重新生成菜单内容。
    private func popUpMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - 菜单动作

    @objc private func revealAccessibilitySettings() {
        SystemSettingsLink.accessibility.open()
    }

    @objc private func revealScreenRecordingSettings() {
        SystemSettingsLink.screenRecording.open()
    }

    @objc private func revealSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitOrbit() {
        NSApp.terminate(nil)
    }
}

/// 「系统设置 › 隐私与安全性」里 Orbit 需要引导用户去的几个面板。
enum SystemSettingsLink: String {
    case accessibility = "Privacy_Accessibility"
    case screenRecording = "Privacy_ScreenCapture"

    func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
