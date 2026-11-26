//
//  OrbitAppCard.swift
//  Orbit
//
//  One app on the ring.
//

import AppKit
import SwiftUI

struct OrbitAppCard: View {
    let app: AppRecord
    let cardNumber: Int
    /// Render order is also the deck order: later cards sit in front of earlier
    /// cards, so the depth ramp follows the existing spread instead of changing
    /// which card wins an overlap.
    let depthIndex: Int
    let depthCount: Int
    /// Where the card sits on the ring, in radians (0 = 3 o'clock).
    let angle: Double
    let isSelected: Bool
    let isDragging: Bool
    let isVanishing: Bool
    let dragOffset: CGSize
    let onSelect: () -> Void
    let onHoverSelect: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var scatterProgress = 0.0

    private var isDark: Bool { colorScheme == .dark }

    /// Three quiet tiers are enough for the eye to read the fan as a deck.
    /// Selected and dragged states intentionally override these values below.
    private var depthTier: Int {
        guard depthCount > 1 else { return 2 }
        let progress = Double(depthIndex) / Double(depthCount - 1)
        switch progress {
        case ..<0.34: return 0
        case ..<0.67: return 1
        default: return 2
        }
    }

    private var depthOpacity: Double {
        switch depthTier {
        case 0: 0.94
        case 1: 0.97
        default: 1
        }
    }

    private var depthScale: CGFloat {
        switch depthTier {
        case 0: 0.97
        case 1: 0.985
        default: 1
        }
    }

    private var depthContactShadowOpacity: Double {
        switch depthTier {
        case 0: 0.06
        case 1: 0.08
        default: 0.10
        }
    }

    private var depthAmbientShadowOpacity: Double {
        switch depthTier {
        case 0: 0.07
        case 1: 0.10
        default: 0.13
        }
    }

    private var depthAmbientShadowRadius: CGFloat {
        switch depthTier {
        case 0: 12
        case 1: 14
        default: 16
        }
    }

    private var depthAmbientShadowY: CGFloat {
        switch depthTier {
        case 0: 5
        case 1: 6
        default: 8
        }
    }

    /// 卡片跟着扇面转，把底边 —— 也就是那行字 —— 对着中心。
    ///
    /// `angle + .pi / 2` is the full turn that points every card's bottom edge
    /// at the hub. The fraction stays plumbed through
    /// `OrbitPreferences.cardRotationFollow` rather than being folded back into
    /// the constant, because everything downstream — the lit edge, the rim
    /// gradient — is written against whatever it is set to; hardcoding the turn
    /// here would silently break them if it is ever dialled back again.
    private var cardRotation: Angle {
        .radians(rotationRadians)
    }

    private var rotationRadians: Double {
        (angle + .pi / 2) * OrbitPreferences.cardRotationFollow
    }

    /// 中心在卡片自己坐标系里的方向。
    ///
    /// The hub sits at `angle + .pi` from the card in screen space; the card is
    /// then rotated, so what the card itself has to be lit from is that
    /// direction minus its own rotation. Working it out rather than fixing the
    /// light to the bottom edge is what lets the highlight stay pointed at the
    /// hub at any `cardRotationFollow`, including zero.
    private var hubDirection: Double {
        angle + .pi - rotationRadians
    }

    /// 靠中心的那条边，在 `UnitPoint` 里的位置。
    private var hubSide: UnitPoint {
        UnitPoint(x: 0.5 + 0.5 * cos(hubDirection), y: 0.5 + 0.5 * sin(hubDirection))
    }

    private var farSide: UnitPoint {
        UnitPoint(x: 0.5 - 0.5 * cos(hubDirection), y: 0.5 - 0.5 * sin(hubDirection))
    }

    /// 选中的卡片被中心拉近一点 —— 屏幕坐标，所以不跟着卡片一起转。
    private var gravityOffset: CGSize {
        guard isSelected, !isDragging else { return .zero }
        let pull = OrbitPreferences.selectionGravityPull
        return CGSize(width: cos(angle + .pi) * pull, height: sin(angle + .pi) * pull)
    }

    private var shortcutHint: String {
        var hints: [String] = []
        if OrbitPreferences.numericShortcutsEnabled, cardNumber <= 9 {
            hints.append(String(cardNumber))
        }
        if OrbitPreferences.letterShortcutsEnabled, let letter = app.letterShortcut {
            hints.append(String(letter).lowercased())
        }
        return hints.joined(separator: " · ")
    }

    /// 卡片底下那行字：平时是快捷键，选中之后换成应用名。
    ///
    /// 换而不是加：the shortcut is what you needed while you were still looking
    /// for this card, and it is the one thing you no longer need once you have
    /// found it. Swapping keeps the card the same height and the fan the same
    /// shape, so confirming what is selected costs no layout at all.
    private var caption: String? {
        if isSelected {
            return app.name
        }
        return shortcutHint.isEmpty ? nil : shortcutHint
    }

    var body: some View {
        let size = OrbitPreferences.cardScale
        let dimension = size.dimension
        let cornerRadius = OrbitRadius.card(dimension)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.iconDimension, height: size.iconDimension)

            Spacer(minLength: 0)

            if let caption {
                Text(caption)
                    .font(.system(size: isSelected ? 11 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? OrbitPalette.accent(on: colorScheme) : hintColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: dimension - 12)
            }
        }
        .padding(.top, dimension * 0.16)
        .padding(.bottom, dimension * 0.1)
        .frame(width: dimension, height: size.height)
        .background(cardBackground(cornerRadius: cornerRadius))
        // 光是从中心来的：靠中心那一侧亮，远端沉下去。这是整个环里唯一一处
        // 说明「哪儿有光源」的地方，也是卡片不再像贴纸的原因。
        .overlay {
            LinearGradient(
                colors: [
                    OrbitPalette.starCore.opacity(lightStrength),
                    .clear
                ],
                startPoint: hubSide,
                endPoint: farSide
            )
            .clipShape(shape)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        // Selection reads through lift, scale and the pull toward the hub; the
        // rim is here so it stays legible without relying on colour alone.
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: rimColors,
                    startPoint: hubSide,
                    endPoint: farSide
                ),
                lineWidth: isSelected ? 1.5 : 1
            )
        )
        // 两层投影：一层贴身的接触影给重量，一层散开的环境影给高度。
        //
        // 一层做不到。A single soft shadow that is dark enough to weigh the card
        // down turns into a bruise, and one light enough to stay clean leaves a
        // white card floating on the pale ground with nothing holding it — which
        // is exactly what the last pass shipped. Splitting the job is how real
        // shadows work and it is the cheapest way to get both.
        // 暗底上投影是白费的 —— 黑影落在暗地上什么也看不出来，还会把叠着的
        // 卡片之间糊得更平。那一档的分离交给边框。
        .shadow(color: isDark ? .clear : contactShadow, radius: isSelected ? 4 : 3, y: 2)
        .shadow(
            color: isDragging ? OrbitPalette.burgundy.opacity(0.24) : .black.opacity(isSelected ? 0.16 : depthAmbientShadowOpacity),
            radius: isSelected ? 22 : depthAmbientShadowRadius,
            y: isSelected ? 11 : depthAmbientShadowY
        )
        .scaleEffect(isSelected ? 1.1 : depthScale)
        .rotationEffect(cardRotation)
        .offset(gravityOffset)
        .offset(dragOffset)
        .opacity(isVanishing ? 0.35 : (isSelected || isDragging ? 1 : depthOpacity))
        // Particles are drawn in unrotated screen space, so aim them straight
        // at the ring center rather than at the card's own bottom edge.
        .cardScatter(progress: scatterProgress, towards: angle + .pi)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in onDragChanged(value.translation) }
                .onEnded { _ in onDragEnded() }
        )
        .onHover { isHovering in
            if isHovering && !isDragging {
                onHoverSelect()
            }
        }
        .onChange(of: isVanishing) { _, newValue in
            if newValue {
                withAnimation(.easeIn(duration: OrbitPreferences.dispersionDuration)) {
                    scatterProgress = 1
                }
            } else {
                scatterProgress = 0
            }
        }
        // 正在消散的卡片不再接受悬停、点击和拖拽。
        .allowsHitTesting(!isVanishing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(app.name))
        .accessibilityHint(Text(isSelected ? "accessibility.selected" : "accessibility.select"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let material: AnyShapeStyle
        switch OrbitPreferences.cardFinish {
        case .white:
            // 拖起来的那张变象牙，是原本就有的手感提示；静止那张也从纯白退到
            // 近白。
            //
            // 纯白是没有余地的颜色。With the wash behind it pulled down, a card
            // at 1.0 becomes the brightest thing on the screen by a margin and
            // the fan reads as a row of light boxes rather than as paper. Half a
            // step down still reads as a white card and leaves the hub — the one
            // thing that is supposed to be emitting — somewhere to be brighter
            // than.
            material = AnyShapeStyle(isDragging ? OrbitPalette.ivory : OrbitPalette.paper)
        case .black:
            material = AnyShapeStyle(Color.black.opacity(0.86))
        case .system:
            material = AnyShapeStyle(.regularMaterial)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(material)
    }

    private var hintColor: Color {
        switch OrbitPreferences.cardFinish {
        case .white: .black.opacity(0.42)
        case .black: .white.opacity(0.55)
        case .system: .secondary
        }
    }

    /// 打在卡片上的光有多强 —— 白卡片本来就亮，再加光只会糊掉。
    ///
    /// 明显比第一版轻。The light source is an ivory bead now, not a burning
    /// core, and a white card lit hard by a pale light just loses its own edge.
    private var lightStrength: Double {
        let base: Double = switch OrbitPreferences.cardFinish {
        // 白面上几乎不加：它已经快到顶了，任何 `plusLighter` 都只是在推高总亮度，
        // 换不来一点形体。The dark finish is where this actually models anything.
        case .white: 0.03
        case .black: 0.24
        case .system: 0.12
        }
        return isSelected ? base * 1.5 : base
    }

    /// 贴着卡片底边那一道接触影。
    private var contactShadow: Color {
        .black.opacity(isSelected ? 0.16 : depthContactShadowOpacity)
    }

    /// 边框也跟着光走：向着中心的那条边接住高光，背光的一边收在主色的发丝线上。
    ///
    /// 未选中那根线用 Welcome 的 0.18。It is the weight the onboarding
    /// illustration outlines everything with, and it is what keeps a white card
    /// on a warm white ground from having to rely on its shadow alone.
    ///
    /// 暗底上换成白线，而且要比浅色那根更实。
    ///
    /// An accent hairline at 0.18 is invisible against a dark ground, so the
    /// shadow side has to swap material rather than just get louder. It also has
    /// to do more work there: **a shadow cast onto a dark ground is not visible
    /// at all**, so on the dark theme the rim is the *only* thing separating one
    /// black card from the black card overlapping it — and the fan's lower arm
    /// is where three or four of them stack. In light the shadow carries that
    /// job and the rim can stay a whisper.
    private var rimColors: [Color] {
        let far: Color = if isSelected {
            OrbitPalette.accent(on: colorScheme).opacity(0.85)
        } else if isDark {
            .white.opacity(0.26)
        } else {
            OrbitPalette.burgundy.opacity(0.18)
        }
        return [.white.opacity(isSelected ? 0.9 : 0.75), far]
    }
}
