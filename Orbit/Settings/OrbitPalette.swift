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
    /// The original Orbit accent. It remains the fallback when a user has not
    /// chosen a custom color yet.
    static let defaultBurgundy = Color(red: 0.56, green: 0.19, blue: 0.17)

    /// The live accent used by the ring, settings window, and previews.
    static var burgundy: Color { OrbitConfig.accentColor }
    /// The wash behind the fan. Follows the accent until it is set on its own.
    static var backdrop: Color { OrbitConfig.ringBackdropColor }
    static let denim = Color(red: 0.69, green: 0.80, blue: 0.85)
    static let ivory = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let coral = Color(red: 0.91, green: 0.60, blue: 0.53)
}
