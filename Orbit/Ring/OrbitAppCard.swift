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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scatterProgress = 0.0

    private var isDark: Bool { colorScheme == .dark }

    /// Three quiet tiers are enough for the eye to read the fan as a deck.
    /// Selected and dragged states intentionally override these values below.
    private var depth: DepthTier {
        guard depthCount > 1 else { return .front }
        let progress = Double(depthIndex) / Double(depthCount - 1)
        switch progress {
        case ..<0.34: return .back
        case ..<0.67: return .middle
        default: return .front
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
                    .foregroundStyle(isSelected ? OrbitPalette.accent(on: colorScheme) : OrbitPreferences.cardFinish.hintColor)
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
            color: isDragging ? OrbitPalette.burgundy.opacity(0.24) : .black.opacity(isSelected ? 0.16 : depth.ambientShadowOpacity),
            radius: isSelected ? 22 : depth.ambientShadowRadius,
            y: isSelected ? 11 : depth.ambientShadowY
        )
        .scaleEffect(isSelected ? 1.1 : depth.scale)
        .rotationEffect(cardRotation)
        .offset(gravityOffset)
        .offset(dragOffset)
        .opacity(isVanishing ? 0.35 : (isSelected || isDragging ? 1 : depth.opacity))
        // Particles are drawn in unrotated screen space, so aim them straight
        // at the ring center rather than at the card's own bottom edge.
        .cardScatter(progress: scatterProgress, towards: angle + .pi, fragments: !reduceMotion)
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
                // 减弱动态效果时只淡出，不碎开。
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .easeIn(duration: OrbitPreferences.dispersionDuration)
                ) {
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(OrbitPreferences.cardFinish.face(isLifted: isDragging))
    }

    private var lightStrength: Double {
        let base = OrbitPreferences.cardFinish.lightStrength
        return isSelected ? base * 1.5 : base
    }

    /// 贴着卡片底边那一道接触影。
    private var contactShadow: Color {
        .black.opacity(isSelected ? 0.16 : depth.contactShadowOpacity)
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

/// 卡片只在它自己的输入变了时才重画。
///
/// The callbacks are rebuilt on every pass of the ring and closures cannot be
/// compared, so without this every card body re-ran whenever anything on the
/// ring changed — including each pointer move of a drag that only one card
/// takes part in. The callbacks only ever act on `app`, which compares by
/// identity, and on its position, which `angle` and `cardNumber` stand for.
extension OrbitAppCard: Equatable {
    static func == (lhs: OrbitAppCard, rhs: OrbitAppCard) -> Bool {
        lhs.app == rhs.app
            && lhs.cardNumber == rhs.cardNumber
            && lhs.depthIndex == rhs.depthIndex
            && lhs.depthCount == rhs.depthCount
            && lhs.angle == rhs.angle
            && lhs.isSelected == rhs.isSelected
            && lhs.isDragging == rhs.isDragging
            && lhs.isVanishing == rhs.isVanishing
            && lhs.dragOffset == rhs.dragOffset
    }
}

/// 卡片按在牌堆里的远近分三档，每一档的透明度、大小和两层投影一起定。
private struct DepthTier {
    let opacity: Double
    let scale: CGFloat
    let contactShadowOpacity: Double
    let ambientShadowOpacity: Double
    let ambientShadowRadius: CGFloat
    let ambientShadowY: CGFloat

    static let back = DepthTier(
        opacity: 0.94, scale: 0.97,
        contactShadowOpacity: 0.06,
        ambientShadowOpacity: 0.07, ambientShadowRadius: 12, ambientShadowY: 5
    )
    static let middle = DepthTier(
        opacity: 0.97, scale: 0.985,
        contactShadowOpacity: 0.08,
        ambientShadowOpacity: 0.10, ambientShadowRadius: 14, ambientShadowY: 6
    )
    static let front = DepthTier(
        opacity: 1, scale: 1,
        contactShadowOpacity: 0.10,
        ambientShadowOpacity: 0.13, ambientShadowRadius: 16, ambientShadowY: 8
    )
}

/// 卡片材质的配色。环上的卡片和设置页的预览卡都从这里取，两边不会各改各的。
extension OrbitPreferences.CardFinish {
    /// 卡面。
    ///
    /// 拖起来的那张白卡片变象牙，是原本就有的手感提示；静止那张也从纯白退到近白。
    ///
    /// 纯白是没有余地的颜色。With the wash behind it pulled down, a card at 1.0
    /// becomes the brightest thing on the screen by a margin and the fan reads
    /// as a row of light boxes rather than as paper. Half a step down still
    /// reads as a white card and leaves the hub — the one thing that is
    /// supposed to be emitting — somewhere to be brighter than.
    func face(isLifted: Bool = false) -> AnyShapeStyle {
        switch self {
        case .white: AnyShapeStyle(isLifted ? OrbitPalette.ivory : OrbitPalette.paper)
        case .black: AnyShapeStyle(Color.black.opacity(0.86))
        case .system: AnyShapeStyle(.regularMaterial)
        }
    }

    /// 卡片底下那行快捷键提示的颜色。
    var hintColor: Color {
        switch self {
        case .white: .black.opacity(0.42)
        case .black: .white.opacity(0.55)
        case .system: .secondary
        }
    }

    /// 打在卡面上的光有多强 —— 白卡片本来就亮，再加光只会糊掉。
    ///
    /// 白面上几乎不加：它已经快到顶了，任何 `plusLighter` 都只是在推高总亮度，
    /// 换不来一点形体。The dark finish is where this actually models anything.
    var lightStrength: Double {
        switch self {
        case .white: 0.03
        case .black: 0.24
        case .system: 0.12
        }
    }
}
