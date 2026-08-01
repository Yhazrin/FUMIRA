import Foundation

struct TimePosition: Hashable, Codable, Sendable {
    static let maximumOffsetDays = 36_525.0
    static let curveExponent = 2.35
    static let now = TimePosition(normalized: 0)

    private static let exactIdentityToleranceDays = 1.0 / (24 * 60 * 60)

    let normalized: Double

    init(normalized: Double) {
        self.normalized = min(max(normalized, -1), 1)
    }

    init(offsetDays: Double) {
        let bounded = min(max(offsetDays, -Self.maximumOffsetDays), Self.maximumOffsetDays)
        let magnitude = pow(abs(bounded) / Self.maximumOffsetDays, 1 / Self.curveExponent)
        normalized = bounded == 0 ? 0 : (bounded < 0 ? -magnitude : magnitude)
    }

    var offsetDays: Double {
        guard normalized != 0 else { return 0 }
        let magnitude = Self.maximumOffsetDays * pow(abs(normalized), Self.curveExponent)
        return normalized < 0 ? -magnitude : magnitude
    }

    var offsetYears: Double {
        offsetDays / 365.25
    }

    /// Exact generation identity, with only enough tolerance for floating-point
    /// and serialization round trips. Product-facing time bands and labels use
    /// their own thresholds and must not use this comparison.
    func hasSameExactTimeIdentity(asOffsetDays otherOffsetDays: Double) -> Bool {
        let ownOffsetDays = offsetDays
        guard ownOffsetDays.isFinite, otherOffsetDays.isFinite else { return false }
        return abs(ownOffsetDays - otherOffsetDays) <= Self.exactIdentityToleranceDays
    }

    func targetDate(from referenceDate: Date = .now, calendar: Calendar = .current) -> Date {
        let seconds = offsetDays * 24 * 60 * 60
        guard seconds.isFinite else { return referenceDate }
        return referenceDate.addingTimeInterval(seconds)
    }

    var compactLabel: String {
        let days = abs(offsetDays)
        guard days.isFinite else { return "NOW" }
        guard days >= 1.0 / 48.0 else { return "NOW" }

        let direction = offsetDays < 0 ? "前" : "后"
        if days < 1 {
            let hours = Int((days * 24).rounded())
            return "\(hours) 小时\(direction)"
        }
        if days < 31 {
            let whole = Int(days.rounded())
            return "\(whole) 天\(direction)"
        }
        if days < 365.25 {
            let months = days / 30.44
            guard months.isFinite else { return "NOW" }
            return String(format: "%.1f 个月%@", months, direction)
        }
        if days < 3_652.5 {
            let years = days / 365.25
            guard years.isFinite else { return "NOW" }
            return String(format: "%.1f 年%@", years, direction)
        }
        let years = (days / 365.25).rounded()
        guard years.isFinite else { return "NOW" }
        return "\(Int(years)) 年\(direction)"
    }
}
