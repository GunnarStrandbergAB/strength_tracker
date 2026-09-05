import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("VerdictConflictRules")
struct VerdictConflictRulesTests {

    private func verdict(_ kind: TrainingVerdict.Kind, active: Bool = false) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: 0, reasons: [], signals: [], action: "a", since: Date(), computedAt: Date(), isActiveDeload: active)
    }

    private func adjustment(_ type: AdjustmentType) -> PlanAdjustment {
        PlanAdjustment(adjustmentType: type, trigger: .apre, description: "d")
    }

    @Test("Increase Weight conflicts with deload and hold, not with progress")
    func increaseRules() {
        #expect(VerdictConflictRules.conflicts(adjustment(.loadIncrease), with: verdict(.deload)))
        #expect(VerdictConflictRules.conflicts(adjustment(.loadIncrease), with: verdict(.hold)))
        #expect(!VerdictConflictRules.conflicts(adjustment(.loadIncrease), with: verdict(.progress)))
        #expect(!VerdictConflictRules.conflicts(adjustment(.loadIncrease), with: nil))
    }

    @Test("Reductions conflict only with a progress verdict or an active deload")
    func reductionRules() {
        #expect(VerdictConflictRules.conflicts(adjustment(.deload), with: verdict(.progress)))
        #expect(VerdictConflictRules.conflicts(adjustment(.loadDecrease), with: verdict(.progress)))
        #expect(!VerdictConflictRules.conflicts(adjustment(.deload), with: verdict(.deload)))
        #expect(!VerdictConflictRules.conflicts(adjustment(.loadDecrease), with: verdict(.hold)))
        #expect(VerdictConflictRules.conflicts(adjustment(.deload), with: verdict(.hold, active: true)))
    }

    @Test("Neutral adjustment types never conflict")
    func neutralTypes() {
        for type in [AdjustmentType.exerciseSwap, .blockExtension, .volumeAdjustment, .frequencyChange, .reforecast] {
            #expect(!VerdictConflictRules.conflicts(adjustment(type), with: verdict(.deload)))
            #expect(!VerdictConflictRules.conflicts(adjustment(type), with: verdict(.progress)))
        }
    }
}
