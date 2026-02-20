import Foundation

// MARK: - Coaching Communication Models (C2)
// Layer 6: Apple Intelligence / FoundationModels integration.
// Plain Codable structs always available. @Generable conformance added when FoundationModels
// is available and used behind availability checks in the coaching service.

/// A coaching explanation for plan adjustments.
public struct CoachingExplanation: Codable, Sendable {
    public var title: String
    public var body: String
    public var tone: String
    public var suggestedAction: String?

    public init(title: String, body: String, tone: String, suggestedAction: String? = nil) {
        self.title = title
        self.body = body
        self.tone = tone
        self.suggestedAction = suggestedAction
    }
}

/// Post-workout summary for user communication.
public struct PostWorkoutSummary: Codable, Sendable {
    public var performanceSummary: String
    public var keyHighlights: [String]
    public var areasForImprovement: [String]
    public var motivationalNote: String

    public init(performanceSummary: String, keyHighlights: [String], areasForImprovement: [String], motivationalNote: String) {
        self.performanceSummary = performanceSummary
        self.keyHighlights = keyHighlights
        self.areasForImprovement = areasForImprovement
        self.motivationalNote = motivationalNote
    }
}

/// Input context for plan creation via natural language.
public struct PlanCreationInput: Codable, Sendable {
    public var userGoalDescription: String
    public var experienceLevel: String
    public var availableDaysPerWeek: Int
    public var equipmentAvailable: [String]
    public var injuriesOrLimitations: [String]

    public init(userGoalDescription: String, experienceLevel: String, availableDaysPerWeek: Int, equipmentAvailable: [String], injuriesOrLimitations: [String]) {
        self.userGoalDescription = userGoalDescription
        self.experienceLevel = experienceLevel
        self.availableDaysPerWeek = availableDaysPerWeek
        self.equipmentAvailable = equipmentAvailable
        self.injuriesOrLimitations = injuriesOrLimitations
    }
}

/// Signals extracted from workout notes via NLP.
public struct WorkoutNoteSignals: Codable, Sendable {
    public var painReported: Bool
    public var fatigueLevel: String?
    public var motivationLevel: String?
    public var sleepQualityMentioned: Bool
    public var injuryMentioned: Bool
    public var rawNotes: String

    public init(painReported: Bool = false, fatigueLevel: String? = nil, motivationLevel: String? = nil, sleepQualityMentioned: Bool = false, injuryMentioned: Bool = false, rawNotes: String = "") {
        self.painReported = painReported
        self.fatigueLevel = fatigueLevel
        self.motivationLevel = motivationLevel
        self.sleepQualityMentioned = sleepQualityMentioned
        self.injuryMentioned = injuryMentioned
        self.rawNotes = rawNotes
    }
}

/// Narrative summary of the entire plan for user communication.
public struct PlanNarrative: Codable, Sendable {
    public var overview: String
    public var weeklyBreakdown: String
    public var progressionStrategy: String
    public var expectedOutcomes: String

    public init(overview: String, weeklyBreakdown: String, progressionStrategy: String, expectedOutcomes: String) {
        self.overview = overview
        self.weeklyBreakdown = weeklyBreakdown
        self.progressionStrategy = progressionStrategy
        self.expectedOutcomes = expectedOutcomes
    }
}
