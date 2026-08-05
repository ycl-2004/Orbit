//
//  PixelDissolveEffect.swift
//  Orbit
//

import SwiftUI

/// 卡片被拖进黑洞时的碎裂消散效果。
///
/// The card itself just fades; the debris is drawn behind it on a `Canvas`, so
/// a few dozen embers cost one draw call instead of a few dozen SwiftUI views.
/// Ember layout is generated once per view size from a fixed seed rather than
/// from `random(in:)` — a re-render mid-animation must not teleport the embers,
/// and a repeatable pattern is far easier to eyeball while tuning.
struct PixelDissolveModifier: ViewModifier {
    /// 消散进度：0 = 完整，1 = 完全消散。
    let progress: Double

    /// 碎片飞向的方向（弧度，相对于卡片中心）。
    let pullDirection: Double

    @State private var embers: [Ember] = []
    @State private var laidOutFor: CGSize = .zero

    /// 一枚碎片的全部静态属性；动画期间只有 `progress` 在变。
    private struct Ember {
        let origin: CGPoint
        let heading: Double
        let reach: CGFloat
        /// 起飞延迟（0–1，归一化到整段进度上），让碎片错开而不是齐步走。
        let liftOff: Double
        let edge: CGFloat
        let warmth: Double
    }

    private enum Motion {
        /// 卡片本体比碎片先消失，免得实心卡片盖住碎片。
        static let cardFadeRate = 1.2
        /// 碎片在这个进度之前不画，让消散有一点起手时间。
        static let debrisOnset = 0.05
        /// 碎片的最大飞行距离（点）。
        static let travel: CGFloat = 100
        /// 碎片自身淡出比位移更快，尾巴不会拖太长。
        static let fadeRate = 1.5
        /// 碎片飞到终点时缩到原尺寸的这个比例。
        static let endScale: CGFloat = 0.5
        static let maxBlur: CGFloat = 2
    }

    func body(content: Content) -> some View {
        content
            .opacity(cardOpacity)
            .background(debrisLayer)
            .blur(radius: CGFloat(progress) * Motion.maxBlur)
    }

    private var cardOpacity: Double {
        guard progress >= Motion.debrisOnset * 2 else { return 1 }
        return max(0, 1 - progress * Motion.cardFadeRate)
    }

    private var debrisLayer: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                guard progress > Motion.debrisOnset else { return }
                for ember in embers {
                    draw(ember, in: &context)
                }
            }
            .onAppear { layOutEmbers(in: geometry.size) }
            .onChange(of: geometry.size) { _, size in layOutEmbers(in: size) }
        }
    }

    private func draw(_ ember: Ember, in context: inout GraphicsContext) {
        // 把整段进度重新映射到"这枚碎片起飞之后"的区间上。
        let flight = (progress - ember.liftOff) / (1 - ember.liftOff)
        guard flight > 0 else { return }

        let distance = ember.reach * CGFloat(flight) * Motion.travel
        let center = CGPoint(
            x: ember.origin.x + cos(ember.heading) * distance,
            y: ember.origin.y + sin(ember.heading) * distance
        )
        let edge = ember.edge * (1 - CGFloat(flight) * Motion.endScale)
        let alpha = max(0, 1 - flight * Motion.fadeRate)
        guard alpha > 0, edge > 0 else { return }

        let box = CGRect(
            x: center.x - edge / 2,
            y: center.y - edge / 2,
            width: edge,
            height: edge
        )

        context.opacity = alpha
        context.fill(
            Path(ellipseIn: box),
            with: .color(Color(red: 1, green: ember.warmth, blue: 0.3).opacity(0.9))
        )
    }

    private func layOutEmbers(in size: CGSize) {
        guard size.width > 0, size.height > 0, size != laidOutFor else { return }
        laidOutFor = size

        var noise = RepeatableNoise(seed: 0x0B17)
        embers = (0 ..< OrbitConfig.dissolveParticleCount).map { index in
            Ember(
                origin: CGPoint(
                    x: noise.next(upTo: size.width),
                    y: noise.next(upTo: size.height)
                ),
                // 大致朝黑洞飞，但散开约 ±0.5 弧度，看起来才像碎裂而不是喷射。
                heading: pullDirection + noise.next(in: -0.5 ... 0.5),
                reach: CGFloat(noise.next(in: 0.5 ... 1.5)),
                liftOff: noise.next(in: 0 ... 0.3),
                edge: CGFloat(noise.next(in: 2 ... 6)),
                // 同一批碎片在金色到橙色之间轻微分层，避免看起来像一整片色块。
                warmth: 0.75 + Double(index % 10) * 0.02
            )
        }
    }
}

/// 一个极小的确定性伪随机数发生器（xorshift64）。
///
/// 只用于摆放视觉碎片，对随机性质量没有要求 —— 要的是同一个种子每次都给出同一
/// 套碎片布局，这样动画不会因为一次重绘而跳变。
private struct RepeatableNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    private mutating func nextUnit() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    mutating func next(upTo bound: CGFloat) -> CGFloat {
        CGFloat(nextUnit()) * bound
    }
}

extension View {
    /// 施加碎裂消散效果。
    /// - Parameters:
    ///   - progress: 消散进度（0–1）。
    ///   - blackHoleDirection: 碎片飞向的方向（弧度）。
    func pixelDissolve(progress: Double, blackHoleDirection: Double = .pi / 2) -> some View {
        modifier(PixelDissolveModifier(progress: progress, pullDirection: blackHoleDirection))
    }
}
