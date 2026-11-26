//
//  OrbitCenterControl.swift
//  Orbit
//
//  The hub at the centre of the ring: its state, label and drop target.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OrbitCenterControl: View {
    let mode: OrbitCenterMode
    /// 选中项换了没有 —— 只用来触发一次脉冲，中心不关心选的是谁。
    let selectionToken: String?
    @Binding var isFileTargeted: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 每次换选中项，星芯轻轻鼓一下。
    ///
    /// Arrowing from one card to the next changes two things far apart on
    /// screen — the card that grew, and the preview that reloaded — and nothing
    /// at the point the eye actually rests. A beat at the centre ties them
    /// together. It has to be small: this fires on every keypress, and anything
    /// with a visible travel becomes a stutter at speed.
    ///
    /// 用关键帧而不是两次 `withAnimation`：在同一拍里先写 `true` 再写 `false`，
    /// SwiftUI 只看见最后的 `false`，跟原来一样，于是什么都不播。
    @State private var pulseCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The forgiving hit target extends beyond the visible hub so a
            // Finder drag does not require pixel-perfect aim.
            Color.clear
                .frame(
                    width: OrbitPreferences.centerDropRadius * 2,
                    height: OrbitPreferences.centerDropRadius * 2
                )
                .contentShape(Circle())

            // 圆点和胶囊之间留够距离，否则整个中心读成一根棒棒糖。
            VStack(spacing: 10) {
                ZStack {
                    hub
                        .frame(
                            width: OrbitPreferences.centerRadius * 2,
                            height: OrbitPreferences.centerRadius * 2
                        )
                        // 鼓起来用弹簧，落回去慢一点，读起来才是"回弹"而不是"抽搐"。
                        .keyframeAnimator(initialValue: 1.0, trigger: pulseCount) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.06, duration: 0.09, spring: Spring(response: 0.16, dampingRatio: 0.5))
                            SpringKeyframe(1.0, duration: 0.3, spring: Spring(response: 0.3, dampingRatio: 0.75))
                        }

                    // 默认状态不戴符号，戴一枚轨道标记。
                    //
                    // A × at the centre of the composition told everyone who
                    // summoned the ring that the likeliest thing they wanted
                    // was to give up, so it went — but an empty bead read as
                    // a placeholder waiting to be filled, which is not what
                    // the anchor of the whole layout should be. The mark is
                    // the product's own idea at its smallest: a ring, and
                    // something on it.
                    if let centerIcon {
                        Image(systemName: centerIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(glyphInk)
                    } else {
                        orbitMark
                    }
                }

                caption
            }
        }
        // 点中心 = 中心当时说它会做的那件事。
        //
        // Switched on the mode rather than filtered by a list of modes it is
        // not: `.confirm` used to fall through to the cancel branch, so a hub
        // painted burgundy, wearing an arrow and captioned "release to switch"
        // dismissed the ring instead. The drag-owned modes still do nothing —
        // the drag's own gestures decide what happens when it is let go.
        .onTapGesture {
            switch mode {
            case .cancel: onCancel()
            case .confirm: onConfirm()
            case .quit, .cleanup, .trash, .share, .failed: break
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isFileTargeted, perform: onDrop)
        .onChange(of: selectionToken) { _, _ in
            guard !reduceMotion else { return }
            pulseCount &+= 1
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(centerLabel))
    }

    /// `nil` 表示这个状态不戴符号。
    private var centerIcon: String? {
        mode == .cancel ? nil : mode.iconName
    }

    /// 空态的中心标记：一圈轨道，上面挂一颗。
    ///
    /// 用形状画而不是拿一个 SF Symbol 凑。The mark has to be the same idea the
    /// dashed arc outside it is drawing, at a twentieth of the size, and no
    /// stock glyph is that. It also stays legible at every card scale because it
    /// is built from the hub's own radius rather than from a font size.
    private var orbitMark: some View {
        let unit = OrbitPreferences.centerRadius
        return ZStack {
            Circle()
                .strokeBorder(OrbitPalette.accent(on: colorScheme).opacity(0.34), lineWidth: 1.2)
                .frame(width: unit * 0.62, height: unit * 0.62)

            Circle()
                .fill(OrbitPalette.accent(on: colorScheme).opacity(0.55))
                .frame(width: unit * 0.16, height: unit * 0.16)
                .offset(y: -unit * 0.31)
        }
    }

    /// 中心下面那行字。
    ///
    /// 默认状态只留一枚键帽。The way out still has to be visible — cutting the
    /// label entirely would trade a hub that shouts "give up" for one that says
    /// nothing about how to leave — but a key cap teaches the keyboard, which is
    /// how the ring is actually driven, instead of advertising the mouse target.
    @ViewBuilder
    private var caption: some View {
        if mode == .cancel {
            // 跟 Welcome 的 `KeycapView` 同一颗键帽：圆角 6，regularMaterial，
            // quaternary 的边。同一个键在两个地方长得一样，才教得会人。
            Text(verbatim: "esc")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        } else {
            Text(centerLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private var centerLabel: String {
        switch mode {
        case .cancel: NSLocalizedString("center.cancel", comment: "")
        case .confirm: NSLocalizedString("center.confirm", comment: "")
        case .quit: NSLocalizedString("center.quit", comment: "")
        case .cleanup: NSLocalizedString("center.cleanup", comment: "")
        case .share: NSLocalizedString("center.share", comment: "")
        case .trash: NSLocalizedString("center.trash", comment: "")
        case .failed: NSLocalizedString("center.failed", comment: "")
        }
    }

    /// 中心是这个场景里唯一的光源，不是一颗按钮。
    ///
    /// 之前它是一块石墨玻璃：构图的圆心上放着画面里最沉的东西，于是整个环没有
    /// 任何地方能解释卡片的高光是从哪儿来的。A core that actually emits — bright
    /// at the centre, falling through the state's hue to a dark edge, with a
    /// corona around it — gives the ring a light source, and it is what every
    /// lit card edge and every glowing trail on screen is now consistent with.
    ///
    /// 状态之间只换色相，不换亮度层级：每个状态共用同一条从亮到暗的梯度，所以
    /// 拖拽穿过中心时它变的是颜色，不是忽明忽暗地跳。The hues also have to stay
    /// deep enough at the edge for a white glyph — `coral` and `denim` are pale
    /// on their own, and the states wearing them (quitting an app, throwing
    /// files away) are the two that can least afford an icon that is hard to
    /// read.
    private var hub: some View {
        ZStack {
            // 象牙底，跟 Welcome 中心那块白色圆角砖是同一种东西 —— 一颗浅色的
            // 珠子，不是一口深色的井。
            //
            // 暗色调下让它透一点，底下的暗透上来，象牙就沉成暖米色。A full-strength
            // cream disc on a dark ground is the brightest thing by a wide
            // margin and reads as a lamp shining into the room; it should be the
            // light *in* the room.
            Circle().fill(OrbitPalette.ivory.opacity(colorScheme == .dark ? 0.72 : 1))

            // 颜色只作为一层很淡的染色浮在上面，中心留白。States差的是色相和
            // 浓度，不是明暗档位，所以拖拽穿过中心时它变色而不是忽明忽暗。
            //
            // 高光收回中心、压低、摊开。An off-centre specular at near-full
            // strength turned the hub into a glossy egg — a rendered object with
            // a light hitting it, sitting in a layout made of flat paper. What
            // it should read as is Welcome's white tile: a calm disc that
            // happens to be the brightest thing on screen.
            Circle().fill(
                RadialGradient(
                    stops: [
                        .init(color: OrbitPalette.starCore.opacity(colorScheme == .dark ? 0.38 : 0.55), location: 0),
                        .init(color: emission.opacity(tintStrength * 0.5), location: 0.55),
                        .init(color: emission.opacity(tintStrength), location: 1)
                    ],
                    center: .init(x: 0.46, y: 0.43),
                    startRadius: 0,
                    endRadius: OrbitPreferences.centerRadius * 1.3
                )
            )
        }
        // Welcome 用 0.28 的发丝线勾它的中心砖，这里就是同一根线。
        .overlay(Circle().strokeBorder(emission.opacity(0.26), lineWidth: 1))
        // 日冕：贴着珠子的一圈很淡的光，说明光是从这里散出去的。
        .overlay {
            Circle()
                .stroke(emission.opacity(0.10), lineWidth: OrbitPreferences.centerRadius * 0.22)
                .blur(radius: OrbitPreferences.centerRadius * 0.24)
                .scaleEffect(1.14)
                .allowsHitTesting(false)
        }
        // 投影按 Welcome 的分量来：一层浅浅的彩色扩散，一层很轻的黑。
        .shadow(color: emission.opacity(0.14), radius: OrbitPreferences.centerRadius * 0.55, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// 这一状态下星芯染的是什么颜色。
    private var emission: Color {
        switch mode {
        case .cancel, .confirm, .cleanup: OrbitPalette.burgundy
        case .quit, .trash, .failed: OrbitPalette.coral
        case .share: OrbitPalette.denim
        }
    }

    /// 符号的颜色。
    ///
    /// 浅色的珠子配不了白符号。`coral` and `denim` are too pale to be read as ink
    /// on ivory either, so the two states wearing them borrow a deeper relative
    /// of the same hue — the states in question are quitting an app and throwing
    /// files away, the two that can least afford a glyph that is hard to read.
    private var glyphInk: Color {
        switch mode {
        case .cancel, .confirm, .cleanup: OrbitPalette.accent(on: colorScheme)
        case .quit, .trash, .failed: OrbitPalette.ember(0.55)
        case .share: colorScheme == .dark ? OrbitPalette.denim : OrbitPalette.denimInk
        }
    }

    /// 默认状态几乎不上色，真的按得下去的状态才明确染上。
    ///
    /// 暗色下整体再收一档：珠子在暗地上本来就是最亮的东西，酒红染上去会把它推向
    /// 粉，而它该读作暖白。
    private var tintStrength: Double {
        let base = rawTintStrength
        return colorScheme == .dark ? base * 0.78 : base
    }

    private var rawTintStrength: Double {
        switch mode {
        case .cancel: 0.10
        case .cleanup: 0.26
        case .confirm: 0.32
        case .share: 0.34
        case .quit, .trash, .failed: 0.40
        }
    }
}
