import Foundation

// MARK: - Protocol

/// C4: Provides coaching explanations for plan adjustments and progress.
/// Two implementations: FoundationModels (Apple Intelligence) and Static (template-based).
public protocol CoachingExplanationProvider: Sendable {
    func explain(adjustment: PlanAdjustment, trainingStatus: TrainingStatus) async -> CoachingExplanation
}

// MARK: - Static Provider (always available)

/// Template-based coaching explanations using pre-written strings.
public struct StaticCoachingProvider: CoachingExplanationProvider, Sendable {

    public init() {}

    public func explain(adjustment: PlanAdjustment, trainingStatus: TrainingStatus) async -> CoachingExplanation {
        let tone = trainingStatus.coachingTone

        let title: String
        let body: String
        let suggestedAction: String?

        switch adjustment.adjustmentType {
        case .deload:
            title = "Recovery Week"
            body = "Your training data suggests it's time for a lighter week. This helps your body adapt and come back stronger."
            suggestedAction = "Complete this week's sessions at the reduced volume."
        case .loadIncrease:
            title = "Weight Increase"
            body = "You're getting stronger! Based on your recent performance, we're increasing the weight."
            suggestedAction = "Focus on maintaining good form at the new weight."
        case .loadDecrease:
            title = "Weight Adjustment"
            body = "We're adjusting the weight down slightly to help you build back up with better form and consistency."
            suggestedAction = "Hit all your reps cleanly this week."
        case .exerciseSwap:
            title = "Exercise Change"
            body = "To keep progressing, we're swapping in a variation that targets the same muscles from a different angle."
            suggestedAction = "Start with a lighter weight to learn the movement pattern."
        default:
            title = "Plan Update"
            body = adjustment.description
            suggestedAction = nil
        }

        return CoachingExplanation(title: title, body: body, tone: tone, suggestedAction: suggestedAction)
    }
}

// MARK: - FoundationModels Provider (iOS 26+)

#if canImport(FoundationModels)
import FoundationModels

/// Apple Intelligence-powered coaching using on-device FoundationModels.
@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsCoachingProvider: CoachingExplanationProvider, Sendable {

    public init() {}

    public func explain(adjustment: PlanAdjustment, trainingStatus: TrainingStatus) async -> CoachingExplanation {
        // Future: Use LanguageModelSession to generate context-aware explanations.
        // For now, delegate to static provider as FoundationModels API stabilizes.
        await StaticCoachingProvider().explain(adjustment: adjustment, trainingStatus: trainingStatus)
    }
}
#endif

// MARK: - Service

/// Routes coaching requests to the appropriate provider based on runtime availability.
public struct CoachingCommunicationService: Sendable {
    private let availabilityService: AppleIntelligenceAvailabilityService

    public init(availabilityService: AppleIntelligenceAvailabilityService = .init()) {
        self.availabilityService = availabilityService
    }

    public var provider: any CoachingExplanationProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), availabilityService.isAvailable {
            return FoundationModelsCoachingProvider()
        }
        #endif
        return StaticCoachingProvider()
    }
}
