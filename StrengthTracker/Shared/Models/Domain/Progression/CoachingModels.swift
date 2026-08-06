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

