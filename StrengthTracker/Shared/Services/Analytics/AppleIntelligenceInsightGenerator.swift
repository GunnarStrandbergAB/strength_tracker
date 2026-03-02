import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Enhanced insight generator that uses Apple Intelligence (Foundation Models)
/// for natural, varied coach-like text on supported devices (iOS 26+, Apple Silicon).
/// Falls back to TemplateInsightGenerator when unavailable.
@available(iOS 26, macOS 26, *)
public final class AppleIntelligenceInsightGenerator: InsightTextGenerating, @unchecked Sendable {

    private let fallback: TemplateInsightGenerator

    public init(fallback: TemplateInsightGenerator) {
        self.fallback = fallback
    }

    @MainActor
    public func generateHighlights(
        trainingLoad: TrainingLoad?,
        overloadTrends: [OverloadTrend],
        deloadRecommendation: DeloadRecommendation?,
        trainingDrift: TrainingDrift?,
        trainingPhase: TrainingPhaseDetection?,
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange]
    ) async -> [AnalyticsHighlight] {
        let templateHighlights = await fallback.generateHighlights(
            trainingLoad: trainingLoad,
            overloadTrends: overloadTrends,
            deloadRecommendation: deloadRecommendation,
            trainingDrift: trainingDrift,
            trainingPhase: trainingPhase,
            recoveryPatterns: recoveryPatterns,
            optimalVolumes: optimalVolumes
        )

        #if canImport(FoundationModels)
        do {
            return try await enhanceHighlights(templateHighlights)
        } catch {
            return templateHighlights
        }
        #else
        return templateHighlights
        #endif
    }

    @MainActor
    public func generateBlockSummary(dimensionDeltas: [DimensionDrift]) async -> String {
        #if canImport(FoundationModels)
        do {
            return try await generateWithModel(
                prompt: "Compare these two training blocks and summarize the key differences in 1-2 sentences as a strength coach would. Dimension changes: \(formatDeltas(dimensionDeltas))"
            )
        } catch {
            return await fallback.generateBlockSummary(dimensionDeltas: dimensionDeltas)
        }
        #else
        return await fallback.generateBlockSummary(dimensionDeltas: dimensionDeltas)
        #endif
    }

    @MainActor
    public func generateDriftExplanation(drift: TrainingDrift) async -> String {
        #if canImport(FoundationModels)
        do {
            let driftInfo = drift.driftingDimensions.map { "\($0.featureName): \(String(format: "%+.2f", $0.delta))" }.joined(separator: ", ")
            return try await generateWithModel(
                prompt: "Explain this training drift to a gym-goer in 1-2 sentences. Overall drift: \(String(format: "%.0f%%", drift.overallDriftScore * 100)). Changes: \(driftInfo)"
            )
        } catch {
            return await fallback.generateDriftExplanation(drift: drift)
        }
        #else
        return await fallback.generateDriftExplanation(drift: drift)
        #endif
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    @MainActor
    private func enhanceHighlights(_ highlights: [AnalyticsHighlight]) async throws -> [AnalyticsHighlight] {
        let session = LanguageModelSession()
        var enhanced: [AnalyticsHighlight] = []

        for highlight in highlights {
            let prompt = "Rewrite this training insight in a concise, motivating coach tone (max 15 words). Type: \(highlight.type.rawValue). Original: \(highlight.detail)"
            do {
                let response = try await session.respond(to: prompt)
                let newDetail = String(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
                enhanced.append(AnalyticsHighlight(
                    type: highlight.type,
                    title: highlight.title,
                    detail: newDetail.isEmpty ? highlight.detail : newDetail
                ))
            } catch {
                enhanced.append(highlight)
            }
        }
        return enhanced
    }

    @MainActor
    private func generateWithModel(prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        let text = String(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { throw AppleIntelligenceError.emptyResponse }
        return text
    }
    #endif

    private func formatDeltas(_ deltas: [DimensionDrift]) -> String {
        deltas.map { "\($0.featureName): \(String(format: "%+.2f", $0.delta))" }.joined(separator: ", ")
    }
}

@available(iOS 26, macOS 26, *)
private enum AppleIntelligenceError: Error {
    case emptyResponse
}
