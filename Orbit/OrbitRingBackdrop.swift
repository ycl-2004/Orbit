//
//  OrbitRingBackdrop.swift
//  Orbit
//
//  The light the cards sit in, shared by the ring itself and the appearance
//  preview in Settings.
//

import SwiftUI

/// 卡片背后那道光晕：沿着扇面铺开的一段辉光，不是一块玻璃。
///
/// 这里换过两次。A disc came first, and at small app counts most of it was
/// empty tinted glass. A band along the fan replaced it and fixed the waste,
/// but not the real problem: the band shared its radius with the cards, so the
/// cards covered nearly all of it, and the only parts that ever reached the eye
/// were the slivers between them — a frosted plate with a rim, seen through
/// gaps, which reads as a smudge that failed to render rather than as anything
/// deliberate.
///
/// So the glass is gone. What is left is light: a few concentric blurred
/// strokes with no edge anywhere, which cannot show a seam between two cards
/// because it has no seam to show. It gives the fan a ground to sit on and a
/// reason for the cards' lit edges, and it stops competing with them for
/// attention. The line that actually says "orbit" is `OrbitTrail`, drawn inside
/// the fan where nothing covers it.
///
/// The ring and the Settings preview both draw through here, so the two cannot
/// drift apart on what the light is made of; the preview only passes a shorter
/// arc.
struct OrbitRingBackdrop: View {
    /// Radius of the glow's centre line — the circle the card centres sit on.
    let radius: CGFloat
    /// Radial thickness of the glow at its widest.
    let thickness: CGFloat
    /// 光晕要盖住的那段角度。
    ///
    /// In `OrbitRingViewModel.angle(for:)`'s convention: 0 is 3 o'clock and the
    /// angle grows clockwise. `Circle`'s own trim starts and runs the same way,
    /// which is what lets the fan's angles be used as the trim directly.
    let arc: ClosedRange<Double>
    let tint: Color

    private var sweep: Double {
        min(max(arc.upperBound - arc.lowerBound, 0), 2 * .pi)
    }

    private var track: some Shape {
        Circle()
            .trim(from: 0, to: sweep / (2 * .pi))
            .rotation(.radians(arc.lowerBound))
    }

    var body: some View {
        ZStack {
            // 两层同心柔光，一层比一层窄、一层比一层实，都糊到没有边为止 ——
            // 只要有一层收出清晰的轮廓，整道光就又变回一条带子了。
            //
            // 浓度按 Welcome 那两团柔光来（0.10–0.13）。On the warm near-white
            // ground the scrim now lays down, anything heavier stops reading as
            // the light the fan is standing in and starts reading as a coloured
            // shape someone drew behind the cards.
            glow(width: thickness * 1.25, blur: thickness * 0.42, color: tint.opacity(0.10))
            glow(width: thickness * 0.72, blur: thickness * 0.26, color: tint.opacity(0.13))
        }
        // The centre line is what the caller positions on the hub; the glow
        // spills well past this frame on purpose.
        .frame(width: radius * 2, height: radius * 2)
        .mask { taper }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(width: CGFloat, blur: CGFloat, color: Color) -> some View {
        track
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .blur(radius: blur)
    }
}

private extension OrbitRingBackdrop {
    /// 两端顺着弧线淡掉，而不是硬生生收在一个圆头上。
    ///
    /// A round cap on a glow this wide reads as a bubble stuck to the end of the
    /// arc. Fading the last tenth of the sweep instead lets the light run out
    /// from under the first and last card, so it ends where the fan does without
    /// announcing it.
    ///
    /// The span has to include the caps, not just the arc between the two end
    /// cards, or a short fan — one app, whose sweep is a few degrees while its
    /// caps are tens — would be masked away almost entirely.
    var taper: some View {
        let capAngle = Double(thickness / 2 / radius)
        let fade = 0.09
        return AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: fade),
                .init(color: .white, location: 1 - fade),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startAngle: .radians(arc.lowerBound - capAngle),
            endAngle: .radians(arc.upperBound + capAngle)
        )
        // 遮罩要比被遮的内容大：辉光本来就溢出自己的 frame 一大截，用同尺寸的
        // 遮罩会把它齐根切掉。
        .frame(width: (radius + thickness * 2) * 2, height: (radius + thickness * 2) * 2)
    }
}
