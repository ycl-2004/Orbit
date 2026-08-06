//
//  SettingsView.swift
//  Orbit
//

import AppKit
import SwiftUI

/// 设置窗口。
///
/// 独立于 SwiftUI 的 `Settings` 场景存在，这样菜单栏菜单里的「设置…」在应用没有
/// 任何窗口、也没有 Dock 图标的情况下也能把窗口叫出来。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.preferredSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("prefs.windowTitle", comment: "Settings window title")
        // 关掉窗口只是把它藏起来；这个控制器是单例，窗口被释放就再也打不开了。
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is not restorable from a nib.")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    static let preferredSize = CGSize(width: 360, height: 620)

    @StateObject private var model = SettingsModel()
    @State private var showsCheatSheet = false

    var body: some View {
        Form {
            accessibilitySection
            triggerSection
            appearanceSection
            previewSection
            startupSection
            cheatSheetSection
        }
        .formStyle(.grouped)
        .tint(OrbitPalette.burgundy)
        .frame(width: 350, height: 610)
        .onAppear { model.reload() }
    }

    // MARK: - 辅助功能权限

    private var accessibilitySection: some View {
        Section {
            HStack {
                Image(systemName: model.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.hasAccessibility ? Color.green : Color.orange)

                Text(model.hasAccessibility ? "prefs.access.granted" : "prefs.access.missing")

                Spacer()

                if !model.hasAccessibility {
                    Button("prefs.access.grant") { SystemSettingsLink.accessibility.open() }
                }
            }
        }
    }

    // MARK: - 触发

    private var triggerSection: some View {
        Section("prefs.group.trigger") {
            // `assignable` rather than `allCases`: picking "Disabled" as the
            // trigger would leave no way to summon the ring at all. The
            // clear-selection picker below does offer it, where it means
            // "no shortcut" rather than "no app".
            Picker("prefs.trigger.key", selection: $model.triggerModifier) {
                ForEach(TriggerModifier.assignable) { modifier in
                    Text(modifier.localizedName).tag(modifier)
                }
            }

            Picker("prefs.trigger.clearKey", selection: $model.clearSelectionModifier) {
                ForEach(model.clearSelectionChoices) { modifier in
                    Text(modifier.localizedName).tag(modifier)
                }
            }

            HStack {
                Text("prefs.trigger.holdTime")
                Slider(value: $model.longPressThreshold, in: 100 ... 300, step: 10)
                Text(String(
                    format: NSLocalizedString("prefs.trigger.holdTimeValue", comment: "Milliseconds"),
                    Int(model.longPressThreshold)
                ))
                .frame(width: 55)
                .monospacedDigit()
            }

            Toggle("prefs.trigger.letterKeys", isOn: $model.letterShortcutsEnabled)
            Toggle("prefs.trigger.numberKeys", isOn: $model.numericShortcutsEnabled)

            Text("prefs.trigger.keysNote")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section("prefs.group.appearance") {
            Picker("prefs.appearance.placement", selection: $model.ringPlacement) {
                ForEach(RingPlacement.allCases) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }

            Picker("prefs.appearance.cardSize", selection: $model.cardSize) {
                ForEach(CardSize.allCases, id: \.self) { size in
                    Text(size.localizedName).tag(size)
                }
            }

            Picker("prefs.appearance.cardFinish", selection: $model.cardMaterial) {
                ForEach(OrbitConfig.CardMaterial.allCases) { material in
                    Text(material.localizedName).tag(material)
                }
            }

            Toggle("prefs.appearance.hideWindowless", isOn: $model.hideWindowlessApps)

            Text("prefs.appearance.hideWindowless.note")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 窗口预览

    private var previewSection: some View {
        Section("prefs.group.preview") {
            Toggle("prefs.preview.enabled", isOn: $model.windowPreviewEnabled)

            if model.windowPreviewEnabled && !model.hasScreenRecording {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("prefs.preview.needsRecording")
                        Button("prefs.preview.openSystemSettings") {
                            SystemSettingsLink.screenRecording.open()
                        }
                    }
                }
                .font(.callout)
            }

            Text("prefs.preview.note")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 开机自启

    private var startupSection: some View {
        Section("prefs.group.startup") {
            Toggle("prefs.startup.launchAtLogin", isOn: $model.launchAtLogin)
        }
    }

    // MARK: - 操作速查

    /// 折叠起来的速查表，内容随开关变化 —— 关掉的快捷键就不该继续出现在说明里。
    private var cheatSheetSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsCheatSheet) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cheatSheetEntries) { entry in
                        SettingsHintRow(systemImage: entry.systemImage, text: entry.text)
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("prefs.group.cheatSheet", systemImage: "keyboard")
            }
        }
    }

    private var cheatSheetEntries: [CheatSheetEntry] {
        var entries: [CheatSheetEntry] = [
            CheatSheetEntry(systemImage: "hand.tap", text: hint("prefs.hint.hold", model.triggerModifier.symbol)),
            CheatSheetEntry(systemImage: "arrow.up.arrow.down", text: hint("prefs.hint.move")),
        ]
        if model.letterShortcutsEnabled {
            entries.append(CheatSheetEntry(systemImage: "character", text: hint("prefs.hint.letters")))
        }
        if model.numericShortcutsEnabled {
            entries.append(CheatSheetEntry(systemImage: "number", text: hint("prefs.hint.numbers")))
        }
        if model.clearSelectionModifier != .disabled {
            entries.append(CheatSheetEntry(
                systemImage: "shift",
                text: hint("prefs.hint.clear", model.clearSelectionModifier.symbol)
            ))
        }
        entries.append(CheatSheetEntry(
            systemImage: "rectangle.portrait.and.arrow.right",
            text: hint("prefs.hint.release")
        ))
        return entries
    }

    /// 取本地化文案。带 `arguments` 时按格式串填充。
    private func hint(_ key: String, _ arguments: CVarArg...) -> String {
        let template = NSLocalizedString(key, comment: "Settings cheat sheet line")
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }
}

private struct CheatSheetEntry: Identifiable {
    let systemImage: String
    let text: String

    var id: String { systemImage }
}

private struct SettingsHintRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OrbitPalette.burgundy)
                .frame(width: 18)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
