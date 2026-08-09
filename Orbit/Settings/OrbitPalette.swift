//
//  OrbitPalette.swift
//  Orbit
//

import AppKit
import SwiftUI

/// Orbit 极小的一组品牌色。
///
/// Surfaces, permission badges, and anything that has to survive a theme switch
/// stay on system materials and semantic colors. These four are reserved for the
/// places where Orbit should look like itself: focus rings, the selected card,
/// and small accents.
enum OrbitPalette {
    /// Shipped accent, used until someone picks a color of their own.
    static let defaultBurgundy = Color(red: 0.56, green: 0.19, blue: 0.17)

    /// The live accent used by the ring, settings window, and previews.
    static var burgundy: Color { OrbitPreferences.accentColor }
    /// The wash behind the fan. Follows the accent until it is set on its own.
    static var backdrop: Color { OrbitPreferences.ringBackdropColor }
    static let denim = Color(red: 0.69, green: 0.80, blue: 0.85)
    /// `denim` 深到能当墨用的那一档。
    ///
    /// The pale blue is a wash colour; on ivory it is not ink. Anywhere a glyph
    /// or a piece of text has to carry the sharing state, it needs this instead.
    static let denimInk = Color(red: 0.29, green: 0.45, blue: 0.55)
    static let ivory = Color(red: 0.97, green: 0.95, blue: 0.91)
    /// 白卡片的纸白 —— 仍然是浅色卡片，但给背景和中心留一点亮度空间。
    ///
    /// Reserved for the card face, which is the largest light surface Orbit
    /// draws and therefore the one that decides how bright the whole ring feels.
    /// It still reads as white beside `ivory`, while the lower luminance keeps a
    /// light desktop from becoming a wall of equal-value whites.
    static let paper = Color(red: 0.965, green: 0.955, blue: 0.940)
    static let coral = Color(red: 0.91, green: 0.60, blue: 0.53)

    /// 暗底上要用的主色。
    ///
    /// 酒红本来就深。On a dark ground it stops being a colour and becomes a hole
    /// — a hairline at 0.18 disappears entirely, a glyph reads as a smudge, and
    /// the dashed orbit, the one mark the product is recognised by, all but
    /// vanishes. Lifting it toward white keeps the hue while giving it somewhere
    /// to sit. Anything that is *ink* on a dark layer goes through here; washes
    /// and fills keep the raw accent, because those are meant to be quiet.
    static func accent(on scheme: ColorScheme) -> Color {
        scheme == .dark ? lifted(burgundy, by: 0.42) : burgundy
    }

    /// 把一个颜色朝白色推一段。
    ///
    /// 手动算而不是用 `Color.mix(with:by:)`：后者要 macOS 15，而这里只是往白端
    /// 走一步，用不着把部署目标抬上去。
    static func lifted(_ color: Color, by amount: Double) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let step = min(max(amount, 0), 1)
        return Color(
            red: Double(rgb.redComponent) + (1 - Double(rgb.redComponent)) * step,
            green: Double(rgb.greenComponent) + (1 - Double(rgb.greenComponent)) * step,
            blue: Double(rgb.blueComponent) + (1 - Double(rgb.blueComponent)) * step
        )
    }

    /// 星芯最亮的那一点。
    ///
    /// The hub is the one light source in the scene, so its core has to sit
    /// above the accent in luminance rather than being the accent again: a core
    /// painted in the accent reads as a flat disc no matter how much glow is
    /// stacked around it. Warm rather than white so the light it casts on the
    /// cards can stay the same hue family as the accent it fades into.
    static let starCore = Color(red: 1.0, green: 0.93, blue: 0.83)

    /// 退出动画里碎片的颜色，`position` 从珊瑚（0）走到酒红（1）。
    ///
    /// 手动插值而不是用 `Color.mix(with:by:)`：后者要 macOS 15，而这里只需要在
    /// 两个已知的常量之间取一点，用不着把部署目标抬上去。
    static func ember(_ position: Double) -> Color {
        let t = min(max(position, 0), 1)
        return Color(
            red: 0.91 + (0.56 - 0.91) * t,
            green: 0.60 + (0.19 - 0.60) * t,
            blue: 0.53 + (0.17 - 0.53) * t
        )
    }
}

/// 圆角的三个档位，整个环上不再有第四个数。
///
/// The ring used to carry three unrelated corner radii — a card at `0.17` of
/// its own width, a 14pt window thumbnail and a 24pt status panel — which is
/// what stopped the two halves of the window from reading as one object. Cards
/// stay proportional because the four card sizes are far enough apart that one
/// fixed radius would look tight on the largest and round on the smallest;
/// everything that has a fixed size shares a fixed token.
enum OrbitRadius {
    /// Large surfaces: the status panel, and anything else the size of a sheet.
    static let surface: CGFloat = 24
    /// Window thumbnails and other content-bearing tiles.
    static let tile: CGFloat = 18
    /// An app card, which scales with the user's card-size setting.
    static func card(_ dimension: CGFloat) -> CGFloat {
        (dimension * 0.18).rounded()
    }
}
