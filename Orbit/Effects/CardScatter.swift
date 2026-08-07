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
        let distance: CGFloat
        let delay: Double
        let size: CGFloat
        let green: Double
    }

    private enum Timing {
        static let particlesAppearAt = 0.08
        static let travelDistance: CGFloat = 92
        static let fadeRate = 1.35
        static let shrinkRate: CGFloat = 0.42
        static let blurRadius: CGFloat = 1.8
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

    private func paint(_ shard: Shard, in context: inout GraphicsContext) {
        let localProgress = (progress - shard.delay) / (1 - shard.delay)
        guard localProgress > 0 else { return }

        let distance = shard.distance * Timing.travelDistance * CGFloat(localProgress)
        let center = CGPoint(
            x: shard.start.x + cos(shard.angle) * distance,
            y: shard.start.y + sin(shard.angle) * distance
        )
        let edge = shard.size * (1 - Timing.shrinkRate * CGFloat(localProgress))
        let opacity = max(0, 1 - localProgress * Timing.fadeRate)
        guard opacity > 0, edge > 0 else { return }

        let rect = CGRect(
            x: center.x - edge / 2,
            y: center.y - edge / 2,
            width: edge,
            height: edge
        )
        context.opacity = opacity
        context.fill(
            Path(roundedRect: rect, cornerRadius: edge * 0.25),
            with: .color(Color(red: 1, green: shard.green, blue: 0.3).opacity(0.9))
        )
    }

    private func arrange(in size: CGSize) {
        guard size.width > 0, size.height > 0, size != measuredSize else { return }
        measuredSize = size

        shards = (0 ..< OrbitConfig.dispersionParticleCount).map { index in
            let sample = ScatterSequence(index: index)
            return Shard(
                start: CGPoint(
                    x: sample.value(for: size.width, axis: 2),
                    y: sample.value(for: size.height, axis: 3)
                ),
                angle: targetAngle + sample.inRange(-0.42 ... 0.42, axis: 5),
                distance: sample.inRange(0.65 ... 1.25, axis: 7),
                delay: sample.inRange(0.02 ... 0.24, axis: 11),
                size: CGFloat(sample.inRange(1.5 ... 5.5, axis: 13)),
                green: sample.inRange(0.73 ... 0.91, axis: 17)
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
