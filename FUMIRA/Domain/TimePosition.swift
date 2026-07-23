import Foundation

struct TimePosition: Hashable, Codable, Sendable {
    static let maximumOffsetDays = 36_525.0
    static let curveExponent = 2.35
    static let now = TimePosition(normalized: 0)

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

    func targetDate(from referenceDate: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: Int(offsetDays.rounded()), to: referenceDate) ?? referenceDate
    }

    var compactLabel: String {
        let days = abs(offsetDays)
        guard days >= 0.5 else { return "NOW" }

        let direction = offsetDays < 0 ? "前" : "后"
        if days < 31 {
            return "\(Int(days.rounded())) 天\(direction)"
        }
        if days < 365.25 {
            return String(format: "%.1f 个月%@", days / 30.44, direction)
        }
        if days < 3_652.5 {
            return String(format: "%.1f 年%@", days / 365.25, direction)
        }
        return "\(Int((days / 365.25).rounded())) 年\(direction)"
    }
}
