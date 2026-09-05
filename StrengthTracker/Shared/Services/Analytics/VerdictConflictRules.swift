import Foundation

/// Decides when a plan suggestion contradicts the shared coach verdict, so the
/// plan screen can annotate (never silently hide) the suggestion.
public enum VerdictConflictRules {

    /// A short note to show under the suggestion, or nil when it agrees with the verdict.
    public static func conflictNote(for adjustment: PlanAdjustment, verdict: TrainingVerdict?) -> String? {
        guard let verdict else { return nil }
        switch adjustment.adjustmentType {
        case .loadIncrease:
            switch verdict.kind {
            case .deload:
                return "Conflicts with the coach verdict (Deload Recommended). Consider holding this increase until the verdict clears."
            case .hold:
                return "The coach verdict is Hold Steady. Applying this increase goes against it."
            case .progress:
                return nil
            }
        case .deload, .loadDecrease:
            if verdict.kind == .progress {
                return "The coach verdict is Clear to Progress; no fatigue signals support this reduction right now."
            }
            if verdict.isActiveDeload, adjustment.adjustmentType == .deload {
                return "A deload is already in progress."
            }
            return nil
        case .blockExtension, .exerciseSwap, .volumeAdjustment, .frequencyChange, .reforecast:
            return nil
        }
    }

    /// True when the suggestion contradicts the verdict.
    public static func conflicts(_ adjustment: PlanAdjustment, with verdict: TrainingVerdict?) -> Bool {
        conflictNote(for: adjustment, verdict: verdict) != nil
    }
}
