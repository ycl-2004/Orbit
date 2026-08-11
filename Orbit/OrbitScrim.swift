//
//  OrbitScrim.swift
//  Orbit
//
//  The layer that puts the ring in a room of its own.
//

import AppKit
import SwiftUI

/// 环周围那一潭柔光：桌面退后，环浮上来。
///
/// The ring used to be drawn straight onto the desktop through a fully
/// transparent panel, which is why a white card over a bright wallpaper never
/// looked like it was floating — it was competing. Every comparable macOS
/// summon layer (Mission Control, the app switcher, Spotlight) pushes the
/// desktop back before it draws anything.
///
/// 铺的是 Welcome 那一页的地，不是一块暗场。The first attempt dimmed toward
/// black, which separated the cards and lost the product: Orbit's own welcome
/// screen is warm near-white with two soft pastel blooms, and a switcher that
/// arrives as a dark room belongs to a different app. Following
/// `windowBackgroundColor` also means it inverts with the system theme.
///
/// 而且它不管可读性。The second attempt made this layer load-bearing for
/// legibility and then had to cover the whole display to do it, which is what
/// broke dragging a file onto the hub: AirDrop and Trash both need the user to
/// go and *find* a file while the ring is open. Every element now carries its
/// own ground — cards are filled, the hub is filled, the empty state has a halo,
/// a thumbnail is opaque — so this layer is free to be what it should have been
/// all along: atmosphere over the part of the screen Orbit is actually using,
/// and nothing at all everywhere else.
struct OrbitScrim: View {
    /// 观察环自己的状态，好跟它一起收场。
    ///
    /// The scrim lives in its own window, so without this it would blink out at
    /// teardown while the cards were still folding back into the hub — the desk
    /// would return before the ring had left it.
    @ObservedObject var model: OrbitRingViewModel
    /// Where the ring's hub lands, in unit coordinates of the full screen.
    let focus: UnitPoint
    /// Orbit 实际画了东西的几块地方，同样是整屏的单位坐标。
    ///
    /// The ring and preview are intentionally separated. A single bounding box
    /// around both creates a bright bridge across the empty middle of the
    /// composition, which is exactly the desktop the user should still be able
    /// to see through.
    let content: [CGRect]
    /// 大片柔光用的颜色 —— 跟着「Backdrop color」走。
    ///
    /// `nil` 表示用户把环的柔光整个关了：veil 留下（它管的是气氛的底），颜色
    /// 撤掉。Keeping a tinted bloom for someone who has just switched the
    /// backdrop off would be answering their setting with a bigger version of
    /// the thing they turned down.
    let bloom: Color?

    @Environment(\.colorScheme) private var colorScheme

    @State private var hasAppeared = false

    private var isRaised: Bool { hasAppeared && !model.isCollapsing }

    /// 关掉透明度的人要的是「看得清」，不是「看不见」：模糊撤掉，底色留下并加实。
    private var reducesTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { proxy in
            layers
                // 把整层收进每一块内容周围独立的潭里。
                //
                // Feathered rather than stopped: each mask reads as a small
                // pool of fog, while the empty space between the two pools stays
                // desktop instead of turning into a white bridge.
                .mask {
                    ZStack {
                        ForEach(Array(content.enumerated()), id: \.offset) { index, rect in
                            // The ring is the visual anchor; the preview supports
                            // it from the opening rather than competing with it.
                            pool(
                                for: rect,
                                in: proxy.size,
                                opacity: poolOpacity(for: index),
                                spread: poolSpread(for: index),
                                feather: poolFeather(for: index)
                            )
                        }
                    }
                }
        }
        .ignoresSafeArea()
        .opacity(isRaised ? presence : 0)
        .animation(.easeOut(duration: 0.16), value: isRaised)
        .animation(.easeOut(duration: 0.18), value: presence)
        .onAppear { hasAppeared = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var layers: some View {
        ZStack {
            if !reducesTransparency && style.drawsBlur {
                OrbitBackdropBlur()
            }

            // 关掉「地」的时候连 Reduce Transparency 的不透明底也一起收。
            //
            // 那条路径存在的理由是「这层在这儿，所以必须让它可读」。If the layer
            // is not there at all, an opaque veil is not an accessibility
            // accommodation — it is the whole thing the user just switched off,
            // reintroduced under another name.
            if style.drawsGround {
                ground
            }
        }
    }

    @ViewBuilder
    private var ground: some View {
        Group {
            // 把局部桌面压进黄昏里。
            //
            // 压暗的颜色不是黑，是 `dusk`。Neutral black over a warm desktop
            // takes its hue out faster than its luminance, so the desk reads as
            // faded rather than dimmed — and a faded desk is still, in value,
            // the same thing as the white cards standing on it. Dimming in the
            // accent's own hue family gives the fan a ground instead.
            //
            // 这一档比上一版重了一倍多。The old 0.08 was tuned to sit under a
            // near-white frosted plate and a coat of ivory; both are gone, so
            // this layer is now the only thing deciding how far back the desk
            // goes, and it has to actually go somewhere.
            if reducesTransparency {
                OrbitPalette.dusk.opacity(opaqueVeilOpacity)
            } else {
                OrbitPalette.dusk.opacity(isDark ? 0.18 : 0.22)
            }

            // 两团柔光，跟 Welcome 同一个配方：主调落在星芯上，另一团在对角
            // 作配重。它们淡到几乎只是「那一块暖一点」，不是可以指出来的形状。
            //
            // 两个主题现在共用一组浓度，因为它们现在落在同一块地上。The light
            // theme used to need its own, quieter numbers to avoid staining a
            // bright desktop; on dusk the same restraint just makes the bloom
            // disappear. Lifting the colour is what keeps it reading as light
            // rather than as a dark patch of dye.
            if let bloom {
                let lit = OrbitPalette.lifted(bloom, by: isDark ? 0.42 : 0.30)

                RadialGradient(
                    colors: [lit.opacity(0.15), lit.opacity(0.035), .clear],
                    center: focus,
                    startRadius: 0,
                    endRadius: 700
                )

                RadialGradient(
                    colors: [OrbitPalette.denim.opacity(0.10), .clear],
                    center: counterweight,
                    startRadius: 0,
                    endRadius: 560
                )
            }
        }
    }

    /// 这层地画到哪一步。见 `OrbitPreferences.ScrimStyle`。
    private var style: OrbitPreferences.ScrimStyle { OrbitPreferences.scrimStyle }

    /// 这一潭的形状：贴着一块 Orbit 内容，往外糊掉。
    ///
    /// 椭圆，不是圆角矩形。A rounded rectangle still has straight runs along its
    /// top and sides, and a straight edge is the one thing the eye can lock onto
    /// through any amount of blur — in the dark theme, where the veil sits at a
    /// far higher contrast against a bright wallpaper than the light one ever
    /// did, the pool became a visible dark panel. An ellipse has no straight
    /// anywhere on it, so there is nothing left to recognise as a shape.
    ///
    /// 适度放大是因为椭圆比它的外接矩形小。The content it has to sit under is
    /// a circular fan or a rounded stage, so the box's corners are empty; a small
    /// expansion gives the content a soft edge without reaching the other pool.
    private func pool(
        for content: CGRect,
        in size: CGSize,
        opacity: Double,
        spread: CGFloat,
        feather: CGFloat
    ) -> some View {
        let box = CGRect(
            x: content.minX * size.width,
            y: content.minY * size.height,
            width: content.width * size.width,
            height: content.height * size.height
        )
        .insetBy(dx: -Self.margin, dy: -Self.margin)

        return Ellipse()
            .fill(.white)
            .frame(
                width: max(box.width, 1) * spread,
                height: max(box.height, 1) * spread
            )
            .position(x: box.midX, y: box.midY)
            .blur(radius: feather)
            .frame(width: size.width, height: size.height)
            .opacity(opacity)
    }

    /// Ring and Preview share one atmosphere, not one brightness level.
    ///
    /// Keeping the mask local preserves the desktop as a usable drop surface;
    /// varying the mask alpha gives the ring a stronger visual anchor while the
    /// preview remains a quieter result field. Reduce Transparency keeps both
    /// pools more opaque so the accessibility setting still delivers contrast.
    private func poolOpacity(for index: Int) -> Double {
        if reducesTransparency {
            return index == 0 ? 0.98 : 0.90
        }
        if isDark {
            return index == 0 ? 0.88 : 0.74
        }
        return index == 0 ? 0.80 : 0.66
    }

    /// The ring can carry a wider, softer field; Preview benefits from a
    /// tighter field so the gap reads as intentional desktop instead of glow.
    private func poolSpread(for index: Int) -> CGFloat {
        index == 0 ? 1.08 : 1.02
    }

    private func poolFeather(for index: Int) -> CGFloat {
        index == 0 ? 92 : 72
    }

    /// 内容外框往外让出的余量、椭圆的放大倍数，以及糊开的半径。
    ///
    /// The feather is the biggest of the three on purpose: it is what turns a
    /// shape into a pool. Most of the reach is ramp, so it reads as light
    /// gathering around the ring rather than as a panel with soft corners.
    private static let margin: CGFloat = 24

    /// 配重那一团摆在星芯的对角，越过屏幕中心一点点。
    private var counterweight: UnitPoint {
        UnitPoint(
            x: min(max(1 - focus.x + 0.12, 0), 1),
            y: min(max(1 - focus.y + 0.18, 0), 1)
        )
    }

    /// 整层现在有多少存在感。
    ///
    /// 拖着文件的时候让路。Once a drag is over the hub the user is working
    /// between two places at once — the file they picked up and the target they
    /// are aiming at — and anything softening the desk between them is in the
    /// way. The pool has already done its job by then.
    private var presence: Double {
        model.fileDropPhase == .resting ? 1 : 0.35
    }

    /// 关闭透明度时才使用不透明底，否则系统的可读性设置不会真正生效。
    ///
    /// 这条路径两个主题下都收到近乎不透明的 `dusk`。The setting is asking for
    /// contrast, and a white card on an almost-opaque dusk ground is the most
    /// contrast this composition can offer — more than the light theme's old
    /// window-background veil, which put a white plate behind white cards.
    private var opaqueVeilOpacity: Double {
        isDark ? 0.94 : 0.88
    }
}

/// 桌面的实时模糊。
///
/// `NSVisualEffectView` blending behind the window is the only thing on this
/// platform that actually blurs what is *underneath* a borderless panel;
/// SwiftUI's own materials only blur siblings inside the same window.
/// `underWindowBackground` is intended for a view that reveals what is under
/// a window. Together with behind-window blending it keeps the desktop
/// readable without introducing an opaque white plate.
///
/// 外观钉死在暗的一档，不跟系统翻。Every `NSVisualEffectView` material is two
/// materials wearing one name, and the light one is a near-white frosted plate
/// — the single largest white surface Orbit was drawing, and it was underneath
/// everything else. 这层是「地」，不是「纸」: pinning it means the blur only ever
/// contributes blur and shade, and the exact colour of the ground is decided by
/// `OrbitPalette.dusk` above it rather than by whichever variant AppKit picked.
///
/// Source: https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground
private struct OrbitBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
