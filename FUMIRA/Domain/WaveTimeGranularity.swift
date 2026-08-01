import CoreGraphics
import Foundation

/// A transient zoom level for the continuous time rail.
///
/// The rail remains bounded to ±100 years. Pulling vertically changes how much
/// time a full-width horizontal gesture covers, so the same physical control can
/// move across years or resolve a specific hour without adding a settings mode.
enum WaveTimeGranularity: Int, CaseIterable, Sendable, Equatable {
    case year
    case month
    case day
    case hour

    static let verticalStep: CGFloat = 28

    /// Advances exactly one precision level and holds at the finest boundary.
    var finer: WaveTimeGranularity {
        WaveTimeGranularity(
            rawValue: min(rawValue + 1, Self.hour.rawValue)
        ) ?? self
    }

    /// Retreats exactly one precision level and holds at the coarsest boundary.
    var coarser: WaveTimeGranularity {
        WaveTimeGranularity(
            rawValue: max(rawValue - 1, Self.year.rawValue)
        ) ?? self
    }

    var snapIntervalDays: Double {
        switch self {
        case .year: 365.25
        case .month: 30.44
        case .day: 1
        case .hour: 1.0 / 24.0
        }
    }

    /// Fine modes are relative to the value held when the gesture begins.
    /// Year mode keeps the established absolute ±100-year rail mapping.
    var horizontalWindowDays: Double {
        switch self {
        case .year: TimePosition.maximumOffsetDays * 2
        case .month: 365.25 * 4
        case .day: 60
        case .hour: 2
        }
    }

    func offsetting(verticalTranslation: CGFloat) -> WaveTimeGranularity {
        guard verticalTranslation.isFinite else { return self }
        let stepDelta = Int(
            (-verticalTranslation / Self.verticalStep).rounded(.towardZero)
        )
        let index = min(
            max(rawValue + stepDelta, Self.year.rawValue),
            Self.hour.rawValue
        )
        return WaveTimeGranularity(rawValue: index) ?? self
    }

    func position(
        from start: TimePosition,
        horizontalTranslation: CGFloat,
        usableWidth: CGFloat
    ) -> TimePosition {
        let width = max(usableWidth, 1)
        let delta = Double(horizontalTranslation / width) * horizontalWindowDays
        return TimePosition(offsetDays: start.offsetDays + delta)
    }

    func snap(_ position: TimePosition) -> TimePosition {
        let interval = snapIntervalDays
        let snappedDays = (position.offsetDays / interval).rounded() * interval
        return TimePosition(offsetDays: snappedDays)
    }

    func compactValueLabel(
        for position: TimePosition,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let date = position.targetDate(from: referenceDate, calendar: calendar)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: date
        )
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0

        switch self {
        case .year:
            return String(format: "%04d", year)
        case .month:
            return String(format: "%04d.%02d", year, month)
        case .day:
            return String(format: "%02d.%02d", month, day)
        case .hour:
            return String(format: "%02d.%02d %02d:00", month, day, hour)
        }
    }
}
