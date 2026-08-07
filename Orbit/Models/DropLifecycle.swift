//
//  DropLifecycle.swift
//  Orbit
//

import Foundation

/// The center control's lifecycle while a file is dragged across the ring.
///
/// URLs intentionally do not live here. They are loaded from the pasteboard only
/// after the user lets go, which keeps hover transitions cheap and prevents a
/// stale asynchronous load from changing the visual state.
enum DropLifecycle: Equatable {
    case resting
    case sharing
    case trashReady
    case processing

    /// Whether the center should accept another drag update right now.
    var acceptsHover: Bool {
        switch self {
        case .sharing, .trashReady:
            return true
        case .resting, .processing:
            return false
        }
    }
}
