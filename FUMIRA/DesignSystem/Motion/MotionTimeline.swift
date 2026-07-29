import SwiftUI

/// The three narrative timelines are intentionally independent. A cancelled
/// camera entrance cannot restart a completed time reveal, and vice versa.
enum MotionTimeline: Equatable, Sendable {
    case none
    case cameraEntry
    case capture
    case timeReveal

    static func transition(from previous: AppPhase, to next: AppPhase) -> Self {
        switch (previous, next) {
        case (.connection, .cameraPermission), (.connection, .viewfinder):
            .cameraEntry
        case (.viewfinder, .shuttered), (.shuttered, .understanding):
            .capture
        case (.generating, .result):
            .timeReveal
        default:
            .none
        }
    }
}
