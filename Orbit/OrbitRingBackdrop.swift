//
//  OrbitRingBackdrop.swift
//  Orbit
//
//  The frosted track the app cards sit on, shared by the ring itself and the
//  appearance preview in Settings.
//

import SwiftUI

/// 卡片背后那条磨砂轨道：只沿着扇面本身铺一条弧带，不再画一整块圆盘。
///
/// A disc has to reach as far in every direction as the fan reaches in one, so
/// at small app counts most of it was empty tinted glass — a plate the cards
/// only ever covered one side of, and the more crowded the desktop behind it,
/// the more colour the material pulled out of it. A band that begins and ends
/// with the fan keeps the cards legible over an arbitrary desktop, leaves the
/// hub and the side facing the preview open, and shortens by itself as apps
/// come and go.
///
/// The ring and the Settings preview both draw through here, so the two can no
/// longer drift apart on what the glass is made of; the preview only passes a
/// shorter arc.
struct OrbitRingBackdrop: View {
    /// Radius of the band's centre line — the circle the card centres sit on.
    let radius: CGFloat
    /// Radial thickness of the band.
    let thickness: CGFloat
    /// 轨道要盖住的那段角度。
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

    /// Round caps are what turn the two ends into the outer edge of a card
    /// rather than a cut, so every layer has to share them.
    private var band: StrokeStyle {
        StrokeStyle(lineWidth: thickness, lineCap: .round)
    }

    var body: some View {
        ZStack {
            // 光晕负责把轨道接回桌布，所以它不能有边：任何轮廓都会读成第二条轨道。
            // 它的半径要跟着带宽走，不然一条细带外面会挂着一圈比它自己还厚的雾。
            track
                .stroke(tint.opacity(0.08), style: band)
                .blur(radius: thickness * 0.15)

            track
                .stroke(.ultraThinMaterial, style: band)
                .overlay {
                    // Lit from the top-left, the same direction the cards are
                    // lit from, so the band sits in the same room as them. The
                    // tint stays a wash — it is here to say the glass is
                    // Orbit's, not to be a colour of its own.
                    track.stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.16),
                                tint.opacity(0.03),
                                tint.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: band
                    )
                }
                .overlay {
                    // The rim follows the band's own stadium outline instead of
                    // a circle, which is the whole point of it: it stops where
                    // the cards stop rather than closing a ring around them.
                    OrbitRingTrackOutline(arc: arc, thickness: thickness)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.30),
                                    tint.opacity(0.10),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.09), radius: 14, y: 8)
        }
        // The centre line is what the caller positions on the hub; the band
        // spills half its thickness either side of this frame on purpose.
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The outline of the stroked band, so a hairline can be drawn along its edge.
private struct OrbitRingTrackOutline: Shape {
    let arc: ClosedRange<Double>
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let sweep = min(max(arc.upperBound - arc.lowerBound, 0), 2 * .pi)
        return Circle()
            .trim(from: 0, to: sweep / (2 * .pi))
            .rotation(.radians(arc.lowerBound))
            .path(in: rect)
            .strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}
