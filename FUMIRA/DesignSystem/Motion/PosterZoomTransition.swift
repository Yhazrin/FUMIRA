import SwiftUI

/// Namespace wrappers for the iOS 18+ ``matchedTransitionSource`` /
/// ``navigationTransition(.zoom)`` pairing. Used for the gear → settings
/// sheet so the panel grows out of the gear instead of sliding up from the
/// bottom edge. On iOS 17 the gear still works, just with the system default
/// sheet transition — both helpers below degrade to identity.
extension View {
    /// Marks the receiver as the source that a paired destination sheet
    /// should zoom out of. Pairs with ``posterZoomDestination(namespace:id:)``.
    /// On iOS 17 this returns the receiver unchanged.
    ///
    /// The optional ``cornerRadius`` clips the destination to a rounded
    /// rectangle during the transition. ``.circle`` clip is not supported
    /// by ``matchedTransitionSource``; pass the desired corner radius of the
    /// destination shape instead.
    @ViewBuilder
    func posterZoomSource(
        namespace: Namespace.ID,
        id: String,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        if #available(iOS 18.0, *) {
            if let cornerRadius {
                matchedTransitionSource(id: id, in: namespace) { configuration in
                    configuration.clipShape(.rect(cornerRadius: cornerRadius))
                }
            } else {
                matchedTransitionSource(id: id, in: namespace)
            }
        } else {
            self
        }
    }

    /// Apply the zoom navigation transition that pairs with
    /// ``posterZoomSource(namespace:id:)``. On iOS 17 this returns the
    /// receiver unchanged so the system default sheet animation is used.
    @ViewBuilder
    func posterZoomDestination(
        namespace: Namespace.ID,
        id: String
    ) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
