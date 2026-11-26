//
//  OrbitPreviewPanel.swift
//  Orbit
//
//  The window carousel beside the ring, and the surfaces it is drawn on.
//

import AppKit
import SwiftUI

/// A compact carousel of every window belonging to the selected app. The
/// selected window stays in front while its neighbours peek out on either
/// side, matching the way a person scans a small stack of related screens.
struct OrbitPreviewPanel: View {
    @ObservedObject var model: OrbitRingViewModel

    @Environment(\.colorScheme) private var colorScheme

    private var selectedIndex: Int {
        guard model.previews.indices.contains(model.selectedWindowIndex) else { return 0 }
        return model.selectedWindowIndex
    }

    private var cardScale: CGSize {
        let width = model.previewCardWidth
        return CGSize(
            width: width,
            height: (width / OrbitPreferences.previewStageAspectRatio).rounded()
        )
    }

    var body: some View {
        Group {
            switch model.previewState {
            // 空态和加载态不给容器。
            //
            // A panel the size of a real preview, holding one icon and two
            // lines, was the largest and emptiest object on the screen — it
            // announced that something was missing rather than quietly waiting
            // for a selection. Dropping the glass keeps the column's width
            // reserved, so nothing jumps when a preview does arrive, while the
            // half itself goes back to being empty space.
            case .idle:
                statusCard(
                    systemName: "square.grid.2x2",
                    titleKey: "preview.empty.title",
                    messageKey: "preview.empty.message",
                    chromeless: true,
                    horizontalOffset: -24
                )
            case .loading:
                statusCard(
                    systemName: "rectangle.inset.filled",
                    titleKey: "preview.loading.title",
                    messageKey: "preview.loading.message",
                    showsProgress: true,
                    chromeless: true
                )
            case .ready:
                carousel
            case .orbit:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.orbit.title",
                    messageKey: "preview.orbit.message",
                    hintKey: "preview.orbit.hint"
                )
            case .screenRecordingRequired:
                statusCard(
                    systemName: "lock.shield",
                    titleKey: "preview.permission.title",
                    messageKey: "preview.permission.message",
                    actionKey: "preview.permission.action",
                    action: SystemSettingsLink.screenRecording.open
                )
            case .noOpenWindows:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.noWindows.title",
                    messageKey: "preview.noWindows.message"
                )
            case .unavailable:
                statusCard(
                    app: model.selectedApp,
                    titleKey: "preview.unavailable.title",
                    messageKey: "preview.unavailable.message"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: model.previews.map(\.id))
        .animation(.easeOut(duration: 0.14), value: model.selectedWindowIndex)
        // Re-running on identity cancels the in-flight capture when the
        // selection moves on, which is the whole debounce we need.
        .task(id: model.selectedID) {
            await model.loadPreviews()
        }
    }

    private var carousel: some View {
        // 翻页器贴到卡片下面来。
        //
        // At 16 with a stage that reserved another 24 of slack, the control sat
        // far enough below the deck to read as a separate object floating on the
        // desktop rather than as this carousel's own pager. Proximity is the
        // whole of the relationship here.
        VStack(spacing: 10) {
            ZStack {
                ForEach(Array(model.previews.enumerated()), id: \.element.id) { index, preview in
                    if let position = deckPosition(for: index) {
                        OrbitPreviewWindowCard(
                            preview: preview,
                            isSelected: index == selectedIndex
                        )
                        .frame(width: cardScale.width, height: cardScale.height)
                        .scaleEffect(position.scale)
                        .offset(position.offset)
                        .opacity(position.opacity)
                        .zIndex(position.zIndex)
                        .transition(.opacity)
                        .onTapGesture { model.selectedWindowIndex = index }
                    }
                }
            }
            .frame(height: cardScale.height + 12)

            if model.previews.count > 1 {
                windowControls
            }
        }
    }

    private var windowControls: some View {
        HStack(spacing: 6) {
            windowStep(systemName: "chevron.left", step: -1)

            Text("\(selectedIndex + 1) / \(model.previews.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 46)

            windowStep(systemName: "chevron.right", step: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    /// A plain tap target rather than a `Button`: the ring window takes key
    /// focus, and a focusable control there would answer Return before the
    /// selected app does.
    private func windowStep(systemName: String, step: Int) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
            .onTapGesture { model.moveWindowSelection(step: step) }
    }

    /// Only the immediate neighbours are drawn. A deeper stack turns into
    /// clutter well before it helps anyone tell two windows apart.
    private func deckPosition(for index: Int) -> (offset: CGSize, scale: CGFloat, opacity: Double, zIndex: Double)? {
        let sideOffset = cardScale.width * OrbitPreferences.previewSideOffsetRatio
        let sideScale = OrbitPreferences.previewSideScale

        switch relativeIndex(for: index) {
        case 0:
            return (.zero, 1, 1, 2)
        case -1:
            return (CGSize(width: -sideOffset, height: 20), sideScale, 0.8, 1)
        case 1:
            return (CGSize(width: sideOffset, height: 20), sideScale, 0.8, 1)
        default:
            return nil
        }
    }

    private func relativeIndex(for index: Int) -> Int {
        let count = model.previews.count
        guard count > 0 else { return 0 }

        let raw = index - selectedIndex
        if raw > count / 2 {
            return raw - count
        }
        if raw < -(count / 2) {
            return raw + count
        }
        return raw
    }

    private func statusCard(
        systemName: String? = nil,
        app: AppRecord? = nil,
        titleKey: String,
        messageKey: String,
        hintKey: String? = nil,
        actionKey: String? = nil,
        action: (() -> Void)? = nil,
        showsProgress: Bool = false,
        chromeless: Bool = false,
        horizontalOffset: CGFloat = 0
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                // 空态连这圈底也不要：一个没有内容的图标不该先给自己盖一个座。
                if !chromeless {
                    Circle()
                        .fill(OrbitPalette.burgundy.opacity(0.11))
                        .frame(width: 74, height: 74)
                }

                if let app {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: chromeless ? 22 : 27, weight: .medium))
                        .foregroundStyle(OrbitPalette.accent(on: colorScheme).opacity(chromeless ? 0.75 : 1))
                }
            }
            .frame(height: chromeless ? 30 : 74)

            VStack(spacing: 5) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // 半透明底上的正文加一档字重 —— 玻璃后面的浅灰细体是这套材质
                // 里最先糊掉的东西。
                Text(LocalizedStringKey(messageKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let hintKey {
                    Text(LocalizedStringKey(hintKey))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrbitPalette.accent(on: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(OrbitPalette.accent(on: colorScheme))
            }

            if let actionKey, let action {
                Text(LocalizedStringKey(actionKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitPalette.accent(on: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(OrbitPalette.accent(on: colorScheme).opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
            }
        }
        // Wide enough to keep the message to a couple of short lines.
        .frame(maxWidth: 420)
        .padding(.horizontal, chromeless ? 18 : 28)
        .padding(.vertical, chromeless ? 12 : 24)
        .modifier(OrbitSurface(enabled: !chromeless))
        .modifier(OrbitTextHalo(enabled: chromeless))
        .offset(x: horizontalOffset)
    }
}

/// 无容器状态背后那团看不出边的底。
///
/// 上一版把空态的玻璃盒去掉是对的，但去得太干净了：文字直接落在桌面上，正好压在
/// 一排文件夹图标之间，读不了。The fix is not to put the box back — an empty
/// state should not occupy the same volume as a full one — it is to give the
/// text a ground the size of the text. A heavily blurred plate in the window's
/// own background colour has no edge anyone can see, costs nothing in perceived
/// weight, and survives any wallpaper underneath it.
struct OrbitTextHalo: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // 这块底大部分时候是叠在那潭柔光上的 —— contentBounds 已经把预览这
            // 一列圈进去了 —— 所以它只需要兜住潭够不到的那一点边缘。
            //
            // 但潭的底换成暖影之后，这层从"别再加亮了"变成了整段文字唯一的依
            // 靠：the status text is `.primary`, which in the light theme is ink
            // on a ground that is no longer pale. 提到 0.34 是让它重新变回一小
            // 块纸 —— 环上其它每样东西都有自己的底，这段字凭什么没有。
            content.background {
                Ellipse()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .opacity(0.34)
                    .blur(radius: 24)
                    .padding(-18)
            }
        } else {
            content
        }
    }
}

/// 预览那一侧的面，跟 Welcome 的卡片同一种做法。
///
/// `.regularMaterial` + `.white.opacity(0.7)` 的边 + 一层很轻的黑影 —— 这三样
/// 是 onboarding 那一页每一块浮起来的东西都在用的配方。The panel used to have a
/// heavier, differently-lit rim than anything else Orbit draws, which is part of
/// why the two halves of the window never read as one object. Sharing the recipe
/// is cheaper than inventing a second one and it is what makes them match.
struct OrbitSurface: ViewModifier {
    let enabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 开了「增强对比度」就把边收实。
    ///
    /// The setting exists for people for whom a 1px hairline at 70% white is not
    /// an edge. Meeting it with a defined border is the documented answer, and it
    /// costs nothing for everyone else because it is off by default.
    private var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    func body(content: Content) -> some View {
        if enabled {
            let shape = RoundedRectangle(cornerRadius: OrbitRadius.surface, style: .continuous)
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(rim, lineWidth: increasesContrast ? 1.5 : 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 18, y: 8)
        } else {
            content
        }
    }

    /// 暗底上 70% 的白边会亮成一根管子；亮底上它才是"光打在玻璃上沿"。
    private var rim: Color {
        if increasesContrast { return .primary.opacity(0.55) }
        return colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.7)
    }
}

/// One window in the carousel. The stage it is handed is the same shape for
/// every window, but the border has to hug the picture — which is a different
/// shape in each. So the artwork floats inside the stage at its own ratio and
/// carries the fill, clip, border and shadow with it. The opaque fill is what
/// keeps a translucent capture readable over the desktop behind it.
struct OrbitPreviewWindowCard: View {
    let preview: WindowPreview
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrbitRadius.tile, style: .continuous)

        Color.clear
            .overlay {
                artwork
                    .aspectRatio(max(preview.aspectRatio, 0.5), contentMode: .fit)
                    .background(OrbitPalette.ivory)
                    .clipShape(shape)
                    // 标题条压在图上，是这张缩略图和它拍的那扇真窗口之间最明确的
                    // 一处不同。
                    //
                    // A capture of a window, shown at a fraction of its size over
                    // a blurred desktop, looks exactly like the window it came
                    // from — in the last build the Terminal preview and the real
                    // Terminal behind it were indistinguishable. A chip Orbit
                    // drew, in Orbit's own material, is the frame that says this
                    // is a picture of a thing rather than the thing.
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            titleChip
                        }
                    }
                    .overlay(
                        shape.stroke(
                            isSelected
                                ? OrbitPalette.burgundy
                                : OrbitPalette.burgundy.opacity(0.22),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    )
                    // 选中的那一张也接住中心的光，跟环上被选中的卡片是同一句话。
                    .shadow(color: .black.opacity(isSelected ? 0.14 : 0.10), radius: 4, y: 2)
                    .shadow(
                        color: isSelected ? OrbitPalette.burgundy.opacity(0.26) : .black.opacity(0.13),
                        radius: isSelected ? 20 : 12,
                        y: isSelected ? 9 : 5
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(preview.title))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var titleChip: some View {
        Text(preview.title)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .padding(.bottom, 10)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = preview.image {
            // Frames are captured in device pixels, so declare that scale
            // rather than letting SwiftUI read them as points and resample.
            Image(decorative: image, scale: preview.scale)
                .resizable()
                .interpolation(.high)
                .opacity(preview.isStale ? 0.75 : 1)
        } else {
            // Nothing capturable and nothing cached — the title is still
            // enough to pick the right window by.
            Color.clear
                .overlay(
                    Text(preview.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(16)
                )
        }
    }
}
