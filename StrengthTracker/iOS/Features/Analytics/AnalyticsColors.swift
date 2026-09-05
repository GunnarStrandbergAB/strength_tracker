#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

extension STColors {
    static let warning = Color(hex: "F59E0B")
    static let info = Color(hex: "60A5FA")
}

/// The one mapping from analytics values to colors, replacing the private
/// helpers that each analytics view used to carry (and that had drifted).
enum AnalyticsColors {
    static func score(_ score: Double) -> Color {
        switch AnalyticsFormatting.scoreBand(score) {
        case .excellent: return STColors.success
        case .good: return STColors.primary
        case .fair: return STColors.warning
        case .poor: return STColors.danger
        }
    }

    static func zone(_ zone: LoadZone) -> Color {
        switch zone {
        case .underTraining: return STColors.info
        case .optimal: return STColors.success
        case .caution: return STColors.warning
        case .danger: return STColors.danger
        }
    }

    static func recovery(_ status: RecoveryStatus) -> Color {
        switch status {
        case .ready: return STColors.success
        case .recovering: return STColors.warning
        case .fatigued: return STColors.danger
        }
    }

    static func severity(_ severity: ImbalanceSeverity) -> Color {
        switch severity {
        case .severe: return STColors.danger
        case .moderate: return STColors.warning
        case .mild: return STColors.info
        }
    }

    static func coaching(_ color: CoachingColor) -> Color {
        switch color {
        case .primary: return STColors.primary
        case .success: return STColors.success
        case .warning: return STColors.warning
        case .danger: return STColors.danger
        case .info: return STColors.info
        }
    }

    static func trend(_ status: TrendStatus) -> Color {
        switch status {
        case .progressing: return STColors.success
        case .plateau: return STColors.warning
        case .regressing: return STColors.danger
        }
    }

    static func highlight(_ type: HighlightType) -> Color {
        switch type {
        case .personalRecord, .milestone: return STColors.primary
        case .streak: return STColors.warning
        case .improvement: return STColors.success
        case .warning: return STColors.danger
        }
    }

    static func highlightIcon(_ type: HighlightType) -> String {
        switch type {
        case .personalRecord: return "trophy.fill"
        case .streak: return "flame.fill"
        case .milestone: return "flag.fill"
        case .improvement: return "arrow.up.right"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}
#endif
