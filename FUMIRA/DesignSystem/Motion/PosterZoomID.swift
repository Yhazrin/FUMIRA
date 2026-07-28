import Foundation

/// Stable identifier namespaces for ``matchedTransitionSource``. Centralized
/// here so source and destination agree on the string, and so we don't
/// accidentally collide with a SwiftUI-internal id.
enum PosterZoomID {
    /// The gear button in any chrome overlay → the settings sheet.
    static let settingsCog = "poster.zoom.settingsCog"
}
