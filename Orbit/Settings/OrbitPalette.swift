//
//  OrbitPalette.swift
//  Orbit
//

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
    static let ivory = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let coral = Color(red: 0.91, green: 0.60, blue: 0.53)

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
