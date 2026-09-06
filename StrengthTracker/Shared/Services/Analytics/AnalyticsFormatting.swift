import Foundation

/// One place for every analytics string so the same number never shows up in two
/// units or two formats ("+2.5 kg/week" vs "+5.5 lb/wk", "1.8x" vs "1.8:1").
/// Pure and stateless; usable from services, views and the widget extension.
public enum AnalyticsFormatting {

    /// Overload slope in the user's unit, e.g. "+2.5 kg/wk".
    public static func slope(kgPerWeek: Double, unit: WeightUnit) -> String {
        String(format: "%+.1f %@/wk", unit.fromKg(kgPerWeek), unit.symbol)
    }

    /// Antagonist ratio, e.g. "1.8:1".
    public static func ratio(_ ratio: Double) -> String {
        String(format: "%.1f:1", ratio)
    }

    /// "3-week streak" / "1-week streak".
    public static func streak(weeks: Int) -> String {
        "\(weeks)-week streak"
    }

    /// Short streak for tight layouts: "3 wk".
    public static func streakShort(weeks: Int) -> String {
        "\(weeks) wk"
    }

    public static func acwr(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// "+12%" / "-5%".
    public static func percentDelta(_ percent: Double) -> String {
        String(format: "%+.0f%%", percent)
    }

    /// "12,500 kg" (grouped, no decimals) in the user's unit.
    public static func volume(kg: Double, unit: WeightUnit) -> String {
        let value = unit.fromKg(kg)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        return "\(number) \(unit.symbol)"
    }

    /// "12.5K kg" / "1.2M lbs" / "850 kg" for badges and widgets.
    public static func compactVolume(kg: Double, unit: WeightUnit) -> String {
        let value = unit.fromKg(kg)
        if value >= 1_000_000 {
            return String(format: "%.1fM %@", value / 1_000_000, unit.symbol)
        } else if value >= 1_000 {
            return String(format: "%.1fK %@", value / 1_000, unit.symbol)
        }
        return String(format: "%.0f %@", value, unit.symbol)
    }

    /// "Stalled 3 weeks" / "Stalled 1 week".
    public static func weeksStalled(_ weeks: Int) -> String {
        "Stalled \(weeks) week\(weeks == 1 ? "" : "s")"
    }

    /// Non-alarmist zone labels. Advice lives in the coach verdict, not here.
    public static func loadZoneLabel(_ zone: LoadZone) -> String {
        switch zone {
        case .underTraining: return "Below baseline"
        case .optimal: return "Near baseline"
        case .caution: return "Above baseline"
        case .danger: return "Well above baseline"
        }
    }

    /// Descriptive (never imperative) explanation of the load zone.
    public static func loadZoneDescription(_ zone: LoadZone, acwr: Double, activeDeload: Bool) -> String {
        if activeDeload {
            return "Deload in progress: load is intentionally below baseline"
        }
        switch zone {
        case .underTraining: return "Load is well below your 28-day baseline"
        case .optimal where acwr < 1.0: return "Recent load is below your smoothed baseline"
        case .optimal: return "Recent load is near or above your smoothed baseline"
        case .caution: return "Load is rising faster than your baseline"
        case .danger: return "Load is far above your baseline"
        }
    }

    /// Shared quality-score bands (80 / 60 / 40) so every ring and bar agrees.
    public enum ScoreBand: Sendable {
        case excellent, good, fair, poor
    }

    public static func scoreBand(_ score: Double) -> ScoreBand {
        switch score {
        case 80...: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return .poor
        }
    }
}
