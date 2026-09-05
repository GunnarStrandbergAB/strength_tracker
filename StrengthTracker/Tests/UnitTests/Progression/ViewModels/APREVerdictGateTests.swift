import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("ProgressionPlanViewModel APRE verdict gate")
@MainActor
struct APREVerdictGateTests {

    private func verdict(_ kind: TrainingVerdict.Kind) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: 0.6, reasons: ["r"], signals: [], action: "Lighter week",
                        since: Date(), computedAt: Date(), isActiveDeload: false)
    }

    private let exerciseId = UUID()

    private var adjustments: [PlanAdjustment] {
        [
            PlanAdjustment(adjustmentType: .loadIncrease, trigger: .apre, description: "up", affectedExerciseIds: [exerciseId], newValues: ["targetWeight": "102.5"]),
            PlanAdjustment(adjustmentType: .loadDecrease, trigger: .apre, description: "down", affectedExerciseIds: [UUID()]),
            PlanAdjustment(adjustmentType: .reforecast, trigger: .oneRMUpdate, description: "1rm", affectedExerciseIds: [exerciseId]),
        ]
    }

    @Test("Deload verdict drops APRE increases and records one reforecast note")
    func deloadDropsIncreases() {
        let gated = ProgressionPlanViewModel.gateAPREIncreases(adjustments, verdict: verdict(.deload))
        #expect(gated.kept.count == 2)
        #expect(!gated.kept.contains { $0.adjustmentType == .loadIncrease })
        #expect(gated.note?.adjustmentType == .reforecast)
        #expect(gated.note?.affectedExerciseIds == [exerciseId])
        #expect(gated.note?.wasAccepted == true)
        #expect(gated.note?.coachingExplanation == "Lighter week")
    }

    @Test("Hold and progress verdicts leave APRE adjustments untouched")
    func holdAndProgressKeep() {
        for kind in [TrainingVerdict.Kind.hold, .progress] {
            let gated = ProgressionPlanViewModel.gateAPREIncreases(adjustments, verdict: verdict(kind))
            #expect(gated.kept.count == 3)
            #expect(gated.note == nil)
        }
        let none = ProgressionPlanViewModel.gateAPREIncreases(adjustments, verdict: nil)
        #expect(none.kept.count == 3)
    }

    @Test("No increases to drop → no note")
    func nothingToDrop() {
        let gated = ProgressionPlanViewModel.gateAPREIncreases(Array(adjustments.dropFirst()), verdict: verdict(.deload))
        #expect(gated.note == nil)
        #expect(gated.kept.count == 2)
    }
}
