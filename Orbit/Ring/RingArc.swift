//
//  RingArc.swift
//  Orbit
//
//  One arc of the ring: the geometry the backdrop glow and the trail share.
//

import SwiftUI

/// 环上的一段弧。光晕和轨道沿同一段弧画，几何只在这里定义一次。
///
/// Angles follow `OrbitRingViewModel.angle(for:)`: 0 is 3 o'clock and the angle
/// grows clockwise. `Circle`'s own trim starts and runs the same way, which is
/// what lets the fan's angles be used as the trim directly.
struct RingArc {
    let range: ClosedRange<Double>

    /// 这段弧扫过的角度，夹在 0 和一整圈之间。
    var sweep: Double {
        min(max(range.upperBound - range.lowerBound, 0), 2 * .pi)
    }

    /// 沿这段弧裁出来的圆，由调用方定尺寸、描边。
    var track: some Shape {
        Circle()
            .trim(from: 0, to: sweep / (2 * .pi))
            .rotation(.radians(range.lowerBound))
    }

    /// 两端顺着弧线淡掉的遮罩。
    ///
    /// - Parameters:
    ///   - fade: 每一端用掉多少比例的弧长来淡入或淡出。
    ///   - overhang: 遮罩两端各比弧多伸出多少弧度，让圆头端点也落在淡出里。
    ///   - size: 遮罩的边长。要比被遮的内容大：溢出自己 frame 的辉光，用同尺寸的
    ///     遮罩会被齐根切掉。
    func taper(fade: Double, overhang: Double = 0, size: CGFloat) -> some View {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: fade),
                .init(color: .white, location: 1 - fade),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startAngle: .radians(range.lowerBound - overhang),
            endAngle: .radians(range.upperBound + overhang)
        )
        .frame(width: size, height: size)
    }
}
