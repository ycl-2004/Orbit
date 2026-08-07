//
//  OrbitApp.swift
//  Orbit
//

import AppKit
import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var delegate

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
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var summonObserver: NSObjectProtocol?

    /// 首次运行后写入的标记；改成 `true` 可以在调试时强制重看欢迎页。
    private static let alwaysShowWelcome = false
    private static let welcomeSeenKey = "hasSeenWelcome"

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不占 Dock 图标，只在菜单栏出现。
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        observeSummonRequests()
        resumeEventTapIfPermitted()
        presentWelcomeIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 用户可能刚在"系统设置"里授予了辅助功能权限。回到前台时重试一次，
        // 这样不用重启 Orbit 快捷键就能生效。
        resumeEventTapIfPermitted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let summonObserver {
            NotificationCenter.default.removeObserver(summonObserver)
        }
        HotKeyService.shared.stopListening()
    }

    /// 只有拿到辅助功能权限时才装事件监听；没权限时反复调用也无副作用。
    private func resumeEventTapIfPermitted() {
        guard HotKeyService.checkAccessibilityPermission() else { return }
        HotKeyService.shared.startListening()
    }

    private func presentWelcomeIfNeeded() {
        let defaults = UserDefaults.standard
        guard Self.alwaysShowWelcome || !defaults.bool(forKey: Self.welcomeSeenKey) else { return }

        // 稍等一拍再弹，让菜单栏图标和事件监听先就位，
        // 否则欢迎窗口可能抢在应用真正激活之前出现。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WelcomeWindowController.shared.show()
            defaults.set(true, forKey: Self.welcomeSeenKey)
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
        item.button?.image = Self.statusItemImage()
        item.button?.target = self
        item.button?.action = #selector(statusItemPressed)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// 菜单栏图标：环 + 中心球，取自 app 图标的骨架。
    ///
    /// Template rendering is what makes it work in the menu bar: macOS throws the
    /// color away and keeps only the alpha, so the same asset inverts for a dark
    /// menu bar and tints while the menu is open. The system symbol behind it is
    /// insurance — a status item with no image is an invisible button, which
    /// would leave the menu unreachable.
    private static func statusItemImage() -> NSImage? {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "Orbit"
        return image
    }

    /// 左键和右键都弹同一个菜单 —— Orbit 没有"点一下就执行"的主操作，
    /// 让两个键行为不同只会让人猜。
    @objc private func statusItemPressed() {
        // 顺手重试一次授权：用户往往是刚授完权就来点菜单栏图标的。
        resumeEventTapIfPermitted()
        popUpMenu(buildMenu())
    }

    private func buildMenu() -> NSMenu {
        let isAuthorized = HotKeyService.checkAccessibilityPermission()
        let menu = NSMenu()

        menu.addItem(infoItem(
            isAuthorized ? "statusMenu.permission.granted" : "statusMenu.permission.missing"
        ))
        menu.addItem(infoItem(String(
            format: NSLocalizedString("statusMenu.hint.hold", comment: "How to summon Orbit"),
            OrbitConfig.triggerModifier.symbol
        )))
        menu.addItem(.separator())

        if !isAuthorized {
            menu.addItem(actionItem("statusMenu.grantAccess", #selector(revealAccessibilitySettings)))
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
