import Foundation
import CryptoKit

@MainActor
public final class WorkoutArchetypeService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    // MARK: - Archetype Clustering (A1)

    public func cluster(vectors: [WorkoutVector], workouts: [Workout], bodyWeightKg: Double) -> [WorkoutArchetype] {
        let completed = workouts.filter { $0.completedAt != nil && !$0.isDeload }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard !completed.isEmpty else { return [] }
        // Explicit templates first; otherwise exact exercise composition. Stable across input order.
        let groups = Dictionary(grouping: completed) { workout in
            workout.templateId?.uuidString ?? workout.exercises.map { $0.exercise.id.uuidString }.sorted().joined(separator: ":")
        }
        let now = Date()
        let cutoff = now.addingTimeInterval(-12 * 7 * 86400)
        let first = completed.map(\.trainingDate).min() ?? cutoff
        let weeks = max(1, now.timeIntervalSince(max(first, cutoff)) / (7 * 86400))
        return groups.keys.sorted().compactMap { key in
            guard let members = groups[key], let representative = members.first else { return nil }
            let ordered = members.sorted { $0.trainingDate > $1.trainingDate }
            let recent = members.filter { $0.trainingDate >= cutoff }
            let names = representative.exercises.sorted { $0.order < $1.order }.map { $0.exercise.name }
            let label = representative.templateId != nil ? (ordered.first?.name ?? representative.name) : names.prefix(2).joined(separator: " + ")
            let memberIds = Set(members.map(\.id))
            let matchingVectors = vectors.filter { memberIds.contains($0.workoutId) }
            let centroid = matchingVectors.isEmpty ? [] : searchService.computeCentroid(vectors: matchingVectors)
            let last = ordered.first!.trainingDate
            return WorkoutArchetype(id: representative.templateId ?? Self.stableID(key), label: label.isEmpty ? "Other sessions" : label,
                centroid: centroid, memberWorkoutIds: ordered.map(\.id), dominantFeatures: names,
                avgVolume: members.reduce(0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) } / Double(members.count),
                avgDuration: members.compactMap(\.duration).reduce(0, +) / Double(members.count),
                frequency: Double(recent.count) / weeks, lastPerformed: last,
                daysSinceLastPerformed: Calendar.current.dateComponents([.day], from: last, to: now).day)
        }.sorted { ($0.lastPerformed ?? .distantPast) > ($1.lastPerformed ?? .distantPast) }
    }

    // MARK: - Training Fingerprint (A6 + A7)

    public func fingerprint(archetypes: [WorkoutArchetype], vectors: [WorkoutVector], recentWeeks: Int = 4) -> TrainingFingerprint? {
        guard !archetypes.isEmpty, vectors.count >= 10 else { return nil }

        let calendar = Calendar.current
        let now = Date()
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -recentWeeks, to: now),
              let priorCutoff = calendar.date(byAdding: .weekOfYear, value: -(recentWeeks * 2), to: now) else {
            return nil
        }

        // Current period distribution
        let recentVectorIds = Set(vectors.filter { $0.createdAt >= cutoff }.map(\.workoutId))
        let priorVectorIds = Set(vectors.filter { $0.createdAt >= priorCutoff && $0.createdAt < cutoff }.map(\.workoutId))

        var currentDist: [String: Double] = [:]
        var priorDist: [String: Double] = [:]

        for archetype in archetypes {
            let recentCount = Double(archetype.memberWorkoutIds.filter { recentVectorIds.contains($0) }.count)
            let priorCount = Double(archetype.memberWorkoutIds.filter { priorVectorIds.contains($0) }.count)
            currentDist[archetype.id.uuidString] = recentCount
            priorDist[archetype.id.uuidString] = priorCount
        }

        // Normalize to proportions
        let currentTotal = max(1, currentDist.values.reduce(0, +))
        let priorTotal = max(1, priorDist.values.reduce(0, +))
        for key in currentDist.keys { currentDist[key]! /= currentTotal }
        for key in priorDist.keys { priorDist[key]! /= priorTotal }

        // Shannon entropy (normalized 0-1)
        let k = Double(archetypes.count)
        let maxEntropy = k > 1 ? log2(k) : 1.0
        let entropy: Double
        if maxEntropy > 0 {
            let h = currentDist.values.reduce(0.0) { sum, p in
                p > 0 ? sum - p * log2(p) : sum
            }
            entropy = h / maxEntropy
        } else {
            entropy = 0
        }

        // Stability: cosine similarity between distributions
        let allLabels = Array(Set(Array(currentDist.keys) + Array(priorDist.keys)))
        let currentVec = allLabels.map { currentDist[$0] ?? 0 }
        let priorVec = allLabels.map { priorDist[$0] ?? 0 }
        let stabilityScore = cosineSimilarity(currentVec, priorVec)

        // Variety trend
        let recentEntropy = entropy
        // Compute prior entropy
        let priorH: Double
        if maxEntropy > 0 {
            let h = priorDist.values.reduce(0.0) { sum, p in
                p > 0 ? sum - p * log2(p) : sum
            }
            priorH = h / maxEntropy
        } else {
            priorH = 0
        }
        let varietyTrend: TrendStatus
        if recentEntropy - priorH > 0.1 { varietyTrend = .progressing }
        else if priorH - recentEntropy > 0.1 { varietyTrend = .regressing }
        else { varietyTrend = .plateau }

        // Consecutive similarity
        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }
        var sims: [Double] = []
        for i in 1..<sorted.count {
            sims.append(cosineSimilarity(sorted[i - 1].dimensions, sorted[i].dimensions))
        }
        let consecutiveSimilarity = sims.isEmpty ? 0 : sims.reduce(0, +) / Double(sims.count)

        return TrainingFingerprint(
            archetypeDistribution: currentDist,
            entropy: entropy,
            stabilityScore: stabilityScore,
            varietyTrend: varietyTrend,
            consecutiveSimilarity: consecutiveSimilarity
        )
    }

    private static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress!) as UUID }
    }

    // MARK: - Helpers

    private func normalize(_ v: [Double]) -> [Double] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }

    private func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        1.0 - cosineSimilarity(a, b)
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard magA > 0 && magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    private func labelFromCentroid(_ centroid: [Double]) -> String {
        // Muscle ratios at dims 6-11: chest, back, legs, shoulders, arms, core
        guard centroid.count >= 12 else { return "Workout" }
        let chest = centroid[6]
        let back = centroid[7]
        let legs = centroid[8]
        let shoulders = centroid[9]
        let arms = centroid[10]
        let core = centroid[11]
        let compound = centroid.count > 12 ? centroid[12] : 0
        let muscleValues = [chest, back, legs, shoulders, arms, core]
        let maxRatio = muscleValues.max() ?? 0
        let minRatio = muscleValues.min() ?? 0
        let diversity = 1.0 - (maxRatio - minRatio)

        if legs > 0.35 { return "Leg Day" }
        if chest > 0.3 && arms > 0.15 { return "Push Day" }
        if back > 0.3 { return "Pull Day" }
        if shoulders > 0.3 { return "Shoulder Day" }
        if maxRatio < 0.25 && diversity > 0.5 { return "Full Body" }
        if compound > 0.6 { return "Heavy Compounds" }
        if arms > 0.35 { return "Arms Day" }
        if core > 0.3 { return "Core Focus" }
        return "Mixed Training"
    }
}
