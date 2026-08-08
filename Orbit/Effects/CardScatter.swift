//
//  CardScatter.swift
//  Orbit
//

import SwiftUI

/// Breaks a card into small warm fragments while it is pulled toward the hub.
///
/// Fragments are laid out once for a given card size. A low-discrepancy sample
/// plus a small integer mix gives a stable field without using global randomness,
/// so a SwiftUI redraw cannot reshuffle the animation halfway through.
struct CardScatterModifier: ViewModifier {
    let progress: Double
    let targetAngle: Double

    @State private var shards: [Shard] = []
    @State private var measuredSize = CGSize.zero

    private struct Shard {
        let start: CGPoint
        let angle: Double
        /// 射程倍率，决定这一片最终飞多远。
        let reach: CGFloat
        /// 加速度指数的增量：越大起步越慢、末段越急，碎片之间的错落全部来自它。
        let drag: Double
        let size: CGFloat
        /// 在 `OrbitPalette.ember` 上的取色位置。
        let tint: Double
    }

    private enum Timing {
        static let particlesAppearAt = 0.08
        static let travelDistance: CGFloat = 96
        static let shrinkRate: CGFloat = 0.45
        static let blurRadius: CGFloat = 1.8
        /// 碎片整体淡出的陡度；大于 1 表示先慢后快。
        static let fadeCurve: Double = 1.6
    }

    func body(content: Content) -> some View {
        content
            .opacity(cardOpacity)
            .background(fragmentLayer)
            .blur(radius: CGFloat(progress) * Timing.blurRadius)
    }

    private var cardOpacity: Double {
        guard progress > 0.08 else { return 1 }
        return max(0, 1 - progress * 1.15)
    }

    private var fragmentLayer: some View {
        GeometryReader { proxy in
            Canvas { context, _ in
                guard progress > Timing.particlesAppearAt else { return }
                for shard in shards {
                    paint(shard, in: &context)
                }
            }
            .onAppear { arrange(in: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in arrange(in: newSize) }
        }
    }

    /// 所有碎片共用一条时间轴 —— 没有哪一片有自己的起跑时刻。
    ///
    /// 错落来自各自的加速曲线：`drag` 把指数抬高，那一片就起步更慢、末段更急，
    /// 像是离中心更远、被拉扯得更晚。这样做的好处是动画在任何一帧被打断（用户
    /// 中途松手、卡片被回收）都还是连续的 —— 而按起跑时刻错开的话，被打断时
    /// 总有一批碎片还停在原地没动过。
    private func paint(_ shard: Shard, in context: inout GraphicsContext) {
        let pull = pow(progress, 1 + shard.drag)
        let distance = shard.reach * Timing.travelDistance * CGFloat(pull)
        let center = CGPoint(
            x: shard.start.x + cos(shard.angle) * distance,
            y: shard.start.y + sin(shard.angle) * distance
        )

        let edge = shard.size * (1 - Timing.shrinkRate * CGFloat(pull))
        let opacity = pow(max(0, 1 - progress), Timing.fadeCurve)
        guard opacity > 0.01, edge > 0 else { return }

        let rect = CGRect(
            x: center.x - edge / 2,
            y: center.y - edge / 2,
            width: edge,
            height: edge
        )
        context.opacity = opacity
        context.fill(
            Path(roundedRect: rect, cornerRadius: edge * 0.25),
            with: .color(OrbitPalette.ember(shard.tint))
        )
    }

    private func arrange(in size: CGSize) {
        guard size.width > 0, size.height > 0, size != measuredSize else { return }
        measuredSize = size

        shards = (0 ..< OrbitPreferences.dispersionParticleCount).map { index in
            let sample = ScatterSequence(index: index)
            return Shard(
                start: CGPoint(
                    x: sample.value(for: size.width, axis: 2),
                    y: sample.value(for: size.height, axis: 3)
                ),
                angle: targetAngle + sample.inRange(-0.42 ... 0.42, axis: 5),
                reach: sample.inRange(0.65 ... 1.25, axis: 7),
                drag: sample.inRange(0 ... 0.9, axis: 11),
                size: CGFloat(sample.inRange(1.5 ... 5.5, axis: 13)),
                tint: sample.inRange(0 ... 1, axis: 17)
            )
        }
    }
}

/// A compact deterministic sampler based on radical inverses and integer mixing.
private struct ScatterSequence {
    let index: Int

    func value(for bound: CGFloat, axis: UInt64) -> CGFloat {
        CGFloat(unit(axis: axis)) * bound
    }

    func inRange(_ range: ClosedRange<Double>, axis: UInt64) -> Double {
        range.lowerBound + unit(axis: axis) * (range.upperBound - range.lowerBound)
    }

    private func unit(axis: UInt64) -> Double {
        var value = UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15 &+ axis
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value % 1_000_003) / 1_000_003
    }
}

extension View {
    /// Adds the short card-to-hub fragment animation used by quit gestures.
    func cardScatter(progress: Double, towards angle: Double = .pi / 2) -> some View {
        modifier(CardScatterModifier(progress: progress, targetAngle: angle))
    }
}
