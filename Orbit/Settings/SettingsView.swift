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
    static let preferredSize = CGSize(width: 600, height: 500)

    @StateObject private var model = SettingsModel()
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane(model: model)
                .tabItem {
                    Label("prefs.tab.general", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ShortcutSettingsPane(model: model)
                .tabItem {
                    Label("prefs.tab.shortcuts", systemImage: "command")
                }
                .tag(SettingsTab.shortcuts)

            AppearanceSettingsPane(model: model)
                .tabItem {
                    Label("prefs.tab.appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)
        }
        .tint(OrbitPalette.burgundy)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .onAppear { model.reload() }
    }
}

private enum SettingsTab: Hashable {
    case general
    case shortcuts
    case appearance
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                AccessibilityStatusRow(model: model)
                AutomationPreauthRow(model: model)
            }

            Section {
                Picker("prefs.language.picker", selection: $model.appLanguage) {
                    Text("language.system").tag(String?.none)
                    Divider()
                    ForEach(AppLanguage.supported, id: \.self) { code in
                        // 语言名用它自己的写法，不跟着界面语言走 —— 见 AppLanguage.autonym。
                        Text(AppLanguage.autonym(code)).tag(String?.some(code))
                    }
                }
                .pickerStyle(.menu)

                if model.languageNeedsRestart {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("prefs.language.restartNote")
                            Button("prefs.language.restart") {
                                model.restart()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            // 新实例没起来时旧的不会退，所以这里说的是"还没换过去"，
                            // 而不是"Orbit 已经没了"。
                            if model.restartFailed {
                                Label("prefs.language.restartFailed", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .font(.callout)
                }
            } header: {
                Text("prefs.group.language")
            }

            Section {
                Picker("prefs.ring.order", selection: $model.ringOrder) {
                    ForEach(RingOrder.allCases) { order in
                        Text(order.localizedName).tag(order)
                    }
                }
                .pickerStyle(.menu)

                Toggle("prefs.ring.preselect", isOn: $model.preselectRecentApp)

                Toggle("prefs.ring.showOrbitCard", isOn: $model.showOrbitCard)
            } header: {
                Text("prefs.group.ring")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("prefs.ring.order.note")
                    Text("prefs.ring.preselect.note")
                    Text("prefs.ring.showOrbitCard.note")
                }
            }

            Section {
                Toggle("prefs.preview.enabled", isOn: $model.windowPreviewEnabled)

                HStack(spacing: 12) {
                    Text("prefs.preview.size")
                    Slider(value: $model.previewScale, in: 0.7 ... 1.5, step: 0.05)
                    Text(String(
                        format: NSLocalizedString("prefs.preview.sizeValue", comment: "Percent"),
                        Int((model.previewScale * 100).rounded())
                    ))
                    .frame(width: 58, alignment: .trailing)
                    .monospacedDigit()
                }
                // 预览不显示时，它有多大不是一个还活着的偏好。
                .disabled(!model.windowPreviewEnabled)

                if model.windowPreviewEnabled && !model.hasScreenRecording {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("prefs.preview.needsRecording")
                            Button("prefs.preview.openSystemSettings") {
                                SystemSettingsLink.screenRecording.open()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .font(.callout)
                }
            } header: {
                Text("prefs.group.preview")
            } footer: {
                Text("prefs.preview.note")
            }

            Section {
                Toggle("prefs.appearance.hideWindowless", isOn: $model.hideWindowlessApps)
                Toggle("prefs.startup.launchAtLogin", isOn: $model.launchAtLogin)
            } footer: {
                Text("prefs.appearance.hideWindowless.note")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccessibilityStatusRow: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.hasAccessibility
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill")
            .foregroundStyle(model.hasAccessibility ? .green : .orange)

            Text(model.hasAccessibility ? "prefs.access.granted" : "prefs.access.missing")
                .foregroundStyle(.secondary)

            Spacer()

            if !model.hasAccessibility {
                Button("prefs.access.grant") {
                    SystemSettingsLink.accessibility.open()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .font(.callout)
    }
}

/// One button that fronts every Automation prompt Orbit would otherwise show
/// mid-switch. The permission is per target app and macOS only asks on first
/// contact — so the first jump into each Chromium-based app used to interrupt
/// the switch with a dialog. Asking here, all at once, is the whole feature.
private struct AutomationPreauthRow: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.badge.checkmark")
                .foregroundStyle(OrbitPalette.burgundy)

            VStack(alignment: .leading, spacing: 6) {
                Text("prefs.automation.note")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("prefs.automation.grantAll") {
                        model.preauthorizeAutomation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.automationPreauth == .running)

                    switch model.automationPreauth {
                    case .idle:
                        EmptyView()
                    case .running:
                        ProgressView()
                            .controlSize(.small)
                    case .nothingToDo:
                        Text("prefs.automation.none")
                            .foregroundStyle(.secondary)
                    case let .finished(granted, denied):
                        Text(String(
                            format: NSLocalizedString("prefs.automation.result", comment: "granted/denied counts"),
                            granted, denied
                        ))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettingsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                // `assignable` rather than `allCases`: picking "Disabled" as the
                // trigger would leave no way to summon the ring at all.
                Picker("prefs.trigger.key", selection: $model.summonKey) {
                    ForEach(ShortcutKey.usableForSummon) { key in
                        Text(key.localizedTitle).tag(key)
                    }
                }
                .pickerStyle(.menu)

                Picker("prefs.trigger.clearKey", selection: $model.clearSelectionKey) {
                    ForEach(model.clearSelectionChoices) { key in
                        Text(key.localizedTitle).tag(key)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 12) {
                    Text("prefs.trigger.holdTime")
                    Slider(value: $model.longPressThreshold, in: 100 ... 300, step: 10)
                    Text(String(
                        format: NSLocalizedString("prefs.trigger.holdTimeValue", comment: "Milliseconds"),
                        Int(model.longPressThreshold)
                    ))
                    .frame(width: 58, alignment: .trailing)
                    .monospacedDigit()
                }

                Toggle("prefs.trigger.letterKeys", isOn: $model.letterShortcutsEnabled)
                Toggle("prefs.trigger.numberKeys", isOn: $model.numericShortcutsEnabled)
            } header: {
                Text("prefs.group.trigger")
            } footer: {
                Text("prefs.trigger.keysNote")
            }

            Section {
                ForEach(cheatSheetEntries(model: model)) { entry in
                    SettingsHintRow(systemImage: entry.systemImage, text: entry.text)
                }
            } header: {
                Text("prefs.group.cheatSheet")
            }
        }
        .formStyle(.grouped)
    }

    private func cheatSheetEntries(model: SettingsModel) -> [CheatSheetEntry] {
        var entries: [CheatSheetEntry] = [
            CheatSheetEntry(systemImage: "hand.tap", text: hint("prefs.hint.hold", model.summonKey.glyph)),
            CheatSheetEntry(systemImage: "arrow.up.arrow.down", text: hint("prefs.hint.move")),
        ]
        if model.letterShortcutsEnabled {
            entries.append(CheatSheetEntry(systemImage: "character", text: hint("prefs.hint.letters")))
        }
        if model.numericShortcutsEnabled {
            entries.append(CheatSheetEntry(systemImage: "number", text: hint("prefs.hint.numbers")))
        }
        if model.clearSelectionKey != .none {
            entries.append(CheatSheetEntry(
                systemImage: "shift",
                text: hint("prefs.hint.clear", model.clearSelectionKey.glyph)
            ))
        }
        entries.append(CheatSheetEntry(
            systemImage: "rectangle.portrait.and.arrow.right",
            text: hint("prefs.hint.release")
        ))
        return entries
    }

    private func hint(_ key: String, _ arguments: CVarArg...) -> String {
        let template = NSLocalizedString(key, comment: "Settings shortcut reference line")
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("prefs.appearance.placement", selection: $model.ringPlacement) {
                    ForEach(RingPlacement.allCases) { placement in
                        Text(placement.localizedName).tag(placement)
                    }
                }
                .pickerStyle(.segmented)

                Picker("prefs.appearance.cardSize", selection: $model.cardSize) {
                    ForEach(CardSize.allCases) { size in
                        Text(size.localizedName).tag(size)
                    }
                }
                .pickerStyle(.menu)

                Picker("prefs.appearance.cardFinish", selection: $model.cardMaterial) {
                    ForEach(OrbitConfig.CardMaterial.allCases) { material in
                        Text(material.localizedName).tag(material)
                    }
                }
                .pickerStyle(.menu)

                ColorPicker(
                    "prefs.appearance.accentColor",
                    selection: $model.accentColor,
                    supportsOpacity: false
                )
            } header: {
                Text("prefs.group.appearance")
            }

            Section {
                Toggle("prefs.appearance.ringBackdrop", isOn: $model.ringBackdropEnabled)

                ColorPicker(
                    "prefs.appearance.ringBackdropColor",
                    selection: $model.ringBackdropColor,
                    supportsOpacity: false
                )
                // A colour for something that is not drawn is a dead control,
                // not a preference worth keeping live.
                .disabled(!model.ringBackdropEnabled)
            } header: {
                Text("prefs.group.ringBackdrop")
            } footer: {
                Text("prefs.appearance.ringBackdrop.note")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                AppearancePreview(
                    cardSize: model.cardSize,
                    cardMaterial: model.cardMaterial,
                    accentColor: model.accentColor,
                    backdropColor: model.ringBackdropEnabled ? model.ringBackdropColor : nil
                )
            } header: {
                Text("prefs.appearance.preview")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePreview: View {
    let cardSize: CardSize
    let cardMaterial: OrbitConfig.CardMaterial
    let accentColor: Color
    /// `nil` when the ring is set to show no backdrop at all.
    let backdropColor: Color?

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                backdrop
                card
            }
            // Sized for the band, not the card: the row has to reserve the
            // space the backdrop takes, or it draws over the label beside it.
            .frame(width: stageSize.width, height: stageSize.height)

            VStack(alignment: .leading, spacing: 4) {
                Text("Orbit")
                    .font(.headline)
                Text("\(cardSize.localizedName) · \(cardMaterial.localizedName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// 真实轨道上、正好托着一张卡片的那一小段。
    ///
    /// The ring's own band is far too large to show whole here — the C only
    /// reads once the stage is about four cards tall, which no settings row
    /// can afford. Drawing the stretch behind a single card through the very
    /// same view is the part that matters: the glass, the wash and the rim are
    /// then the ring's by construction rather than by a copied number.
    @ViewBuilder
    private var backdrop: some View {
        if let backdropColor {
            OrbitRingBackdrop(
                radius: trackRadius,
                thickness: trackThickness,
                arc: (-.pi / 2 - trackHalfSweep)...(-.pi / 2 + trackHalfSweep),
                tint: backdropColor
            )
            // 弧顶在圆心正上方 `trackRadius` 处，所以把圆心压到卡片下面那么远，
            // 弧顶就正好落在卡片身上。
            .offset(y: trackRadius)
        }
    }

    /// Flat enough that the row shows a piece of track rather than a wedge,
    /// curved enough that it is the same shape as the real thing.
    private var trackRadius: CGFloat {
        previewDimension * 3
    }

    /// 跟真实轨道同一条规则：一张卡片那么宽。
    ///
    /// 弧顶朝上，所以这里的「径向」是竖直方向 — 也就是这张不旋转的预览卡片的长边
    /// 方向，正如环上那些卡片的长边指向中心。The card standing a little proud of
    /// the band top and bottom is the real ring's proportion, not a mistake.
    private var trackThickness: CGFloat {
        previewDimension * 0.88
    }

    /// Runs a little past the card at both ends, the way the real band runs
    /// past the first and last app.
    private var trackHalfSweep: Double {
        Double(20 / trackRadius)
    }

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: previewDimension * 0.17, style: .continuous)
                .fill(cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: previewDimension * 0.17, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: previewDimension * 0.17, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.9), lineWidth: 1.5)
                }

            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: previewDimension * 0.47, height: previewDimension * 0.47)
                Text("Orbit")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(cardForeground)
        }
        .frame(width: previewDimension, height: previewDimension * 1.2)
        // Only the card casts one. Shadowing the stack would smear the disc's
        // soft edge into a hard one.
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// Room for whichever is larger, the card or the piece of band behind it.
    /// With the backdrop switched off there is no band to reserve space for.
    private var stageSize: CGSize {
        let card = CGSize(
            width: previewDimension + 16,
            height: previewDimension * 1.2 + 16
        )
        guard backdropColor != nil else { return card }
        let bandLength = trackThickness + 2 * trackRadius * CGFloat(sin(trackHalfSweep))
        return CGSize(
            width: max(card.width, bandLength + 8),
            height: max(card.height, trackThickness + 8)
        )
    }

    /// Keep the preview proportional to a real ring card while making the
    /// four size choices visibly different in a compact settings row.
    private var previewDimension: CGFloat {
        cardSize.dimension * 0.55
    }

    private var cardFill: AnyShapeStyle {
        switch cardMaterial {
        case .white:
            AnyShapeStyle(Color.white)
        case .black:
            AnyShapeStyle(Color.black.opacity(0.86))
        case .system:
            AnyShapeStyle(.regularMaterial)
        }
    }

    private var cardBorder: Color {
        switch cardMaterial {
        case .white:
            .black.opacity(0.06)
        case .black:
            .white.opacity(0.12)
        case .system:
            .white.opacity(0.2)
        }
    }

    private var cardForeground: Color {
        switch cardMaterial {
        case .black:
            .white
        case .white:
            .black.opacity(0.82)
        case .system:
            .primary
        }
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
    }
}
