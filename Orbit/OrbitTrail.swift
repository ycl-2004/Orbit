//
//  OrbitTrail.swift
//  Orbit
//
//  The dashed arc the cards travel on.
//

import SwiftUI

/// 卡片脚下那条虚线轨道，外加每张卡片在轨道上的落点。
///
/// The frosted band this replaces sat on the same radius as the cards, so the
/// cards covered almost all of it and what came through the gaps read as a
/// smudge rather than a track. A line set *inside* the fan is never covered by
/// anything, which is what finally lets the ring say "orbit" without a single
/// extra pixel of chrome.
///
/// 虚线，而且是 Welcome 那一条虚线。The onboarding illustration draws the orbit
/// as a dashed accent ellipse, and it is the single most recognisable mark the
/// product owns. Repeating the exact stroke here means the ring the user is
/// shown on day one and the ring they summon on day two are drawn by the same
/// hand.
///
/// 圆点是后来补的，因为光有弧线不够。An arc floating between the hub and the
/// cards touches neither of them, so it read as a stray shape rather than as the
/// track the fan is standing on. A dot on the line under each card is what makes
/// the relationship legible: the cards stop being an arrangement and become
/// positions on an orbit. The selected one is a filled marker, which is the same
/// sentence the enlarged card is saying, said again where the eye already is.
struct OrbitTrail: View {
    /// Radius of the line itself — inside the cards, outside the hub.
    let radius: CGFloat
    /// 轨道要走的那段角度，跟卡片扇面同一套约定：0 是 3 点钟，顺时针增长。
    let arc: ClosedRange<Double>
    /// 每张卡片所在的角度，用来在轨道上打点。
    let stops: [Double]
    /// 选中的是第几个落点。
    let selectedStop: Int?
    let tint: Color
    /// 0 表示还没展开，轨道跟着卡片一起亮起来。
    var progress: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    private var sweep: Double {
        min(max(arc.upperBound - arc.lowerBound, 0), 2 * .pi)
    }

    private var track: some Shape {
        Circle()
            .trim(from: 0, to: sweep / (2 * .pi))
            .rotation(.radians(arc.lowerBound))
    }

    /// 暗底上同一个酒红会掉一大截，线的存在感要补回来。
    private var lineOpacity: Double {
        colorScheme == .dark ? 0.78 : 0.58
    }

    var body: some View {
        ZStack {
            track
                // Welcome 用的就是这一支笔：2pt，dash [5, 4]。
                .stroke(
                    tint.opacity(lineOpacity),
                    style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [5, 4])
                )
                .frame(width: radius * 2, height: radius * 2)
                // 两端淡出，轨道才是"路过"而不是"起止"。
                .mask { taper }

            ForEach(Array(stops.enumerated()), id: \.offset) { index, angle in
                marker(isSelected: index == selectedStop)
                    .offset(
                        x: cos(angle) * radius,
                        y: sin(angle) * radius
                    )
            }
        }
        // 展开时轨道从中心长出来，跟卡片飞出去是同一个动作的两半。
        .scaleEffect(0.72 + 0.28 * progress)
        .opacity(progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 落点：没选中是一颗空心小点，选中是实心的，外面再套一圈光。
    @ViewBuilder
    private func marker(isSelected: Bool) -> some View {
        if isSelected {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 4)
                        .scaleEffect(1.9)
                }
        } else {
            Circle()
                .fill(tint.opacity(lineOpacity * 0.75))
                .frame(width: 3.5, height: 3.5)
        }
    }

    private var taper: some View {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.14),
                .init(color: .white, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startAngle: .radians(arc.lowerBound),
            endAngle: .radians(arc.upperBound)
        )
        .frame(width: radius * 2 + 8, height: radius * 2 + 8)
    }
}
