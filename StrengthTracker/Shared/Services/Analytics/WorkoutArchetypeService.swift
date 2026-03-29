import Foundation

@MainActor
public final class WorkoutArchetypeService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    // MARK: - Archetype Clustering (A1)

    public func cluster(vectors: [WorkoutVector], workouts: [Workout]) -> [WorkoutArchetype] {
        guard vectors.count >= 10 else { return [] }

        // L2 normalize vectors for cosine distance
        let normalized = vectors.map { normalize($0.dimensions) }

        // Auto-select k: try 2..min(8, n/3), pick best silhouette
        let maxK = min(8, vectors.count / 3)
        guard maxK >= 2 else { return [] }

        var bestK = 2
        var bestScore = -1.0
        var bestAssignments: [Int] = []
        var bestCentroids: [[Double]] = []

        for k in 2...maxK {
            let (assignments, centroids) = kMeans(data: normalized, k: k, maxIterations: 50)
            let score = silhouetteScore(data: normalized, assignments: assignments, k: k)
            if score > bestScore {
                bestScore = score
                bestK = k
                bestAssignments = assignments
                bestCentroids = centroids
            }
        }

        // Build archetypes
        let workoutMap = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        let now = Date()
        let calendar = Calendar.current

        var archetypes: [WorkoutArchetype] = []
        for cluster in 0..<bestK {
            let memberIndices = bestAssignments.enumerated().filter { $0.element == cluster }.map(\.offset)
            guard !memberIndices.isEmpty else { continue }

            let memberVectors = memberIndices.map { vectors[$0] }
            let memberWorkoutIds = memberVectors.map(\.workoutId)
            let memberWorkouts = memberWorkoutIds.compactMap { workoutMap[$0] }

            let centroid = bestCentroids[cluster]
            let label = labelFromCentroid(centroid)

            let avgVolume = memberWorkouts.isEmpty ? 0 :
                memberWorkouts.reduce(0.0) { $0 + $1.totalVolume } / Double(memberWorkouts.count)
            let durations = memberWorkouts.compactMap(\.duration)
            let avgDuration = durations.isEmpty ? 0 :
                durations.reduce(0, +) / Double(durations.count)

            // Frequency: sessions per week over the span of this cluster
            let dates = memberWorkouts.compactMap(\.completedAt).sorted()
            let frequency: Double
            if let first = dates.first, let last = dates.last, first != last {
                let weeks = max(1, calendar.dateComponents([.weekOfYear], from: first, to: last).weekOfYear ?? 1)
                frequency = Double(dates.count) / Double(weeks)
            } else {
                frequency = 0
            }

            let lastPerformed = dates.last
            let daysSince = lastPerformed.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 }

            // Top features by centroid magnitude
            let featureNames = WorkoutVector.featureNames
            let topFeatures = centroid.enumerated()
                .filter { $0.offset < featureNames.count }
                .sorted { abs($0.element) > abs($1.element) }
                .prefix(3)
                .map { featureNames[$0.offset] }

            archetypes.append(WorkoutArchetype(
                label: label,
                centroid: centroid,
                memberWorkoutIds: memberWorkoutIds,
                dominantFeatures: topFeatures,
                avgVolume: avgVolume,
                avgDuration: avgDuration,
                frequency: frequency,
                lastPerformed: lastPerformed,
                daysSinceLastPerformed: daysSince
            ))
        }

        return archetypes.sorted { $0.memberWorkoutIds.count > $1.memberWorkoutIds.count }
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
            currentDist[archetype.label] = recentCount
            priorDist[archetype.label] = priorCount
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

    // MARK: - K-Means

    private func kMeans(data: [[Double]], k: Int, maxIterations: Int) -> ([Int], [[Double]]) {
        guard !data.isEmpty else { return ([], []) }
        let n = data.count
        let d = data[0].count

        // Initialize centroids using k-means++
        var centroids: [[Double]] = []
        centroids.append(data[Int.random(in: 0..<n)])

        for _ in 1..<k {
            var distances = data.map { point -> Double in
                centroids.map { cosineDistance(point, $0) }.min() ?? Double.infinity
            }
            let total = distances.reduce(0, +)
            if total <= 0 {
                centroids.append(data[Int.random(in: 0..<n)])
                continue
            }
            distances = distances.map { $0 / total }

            var rand = Double.random(in: 0..<1)
            var chosen = 0
            for (i, p) in distances.enumerated() {
                rand -= p
                if rand <= 0 { chosen = i; break }
            }
            centroids.append(data[chosen])
        }

        var assignments = [Int](repeating: 0, count: n)

        for _ in 0..<maxIterations {
            // Assign
            var changed = false
            for i in 0..<n {
                let nearest = centroids.enumerated().min(by: {
                    cosineDistance(data[i], $0.element) < cosineDistance(data[i], $1.element)
                })?.offset ?? 0
                if assignments[i] != nearest { changed = true }
                assignments[i] = nearest
            }

            if !changed { break }

            // Update centroids
            for c in 0..<k {
                let members = assignments.enumerated().filter { $0.element == c }.map { data[$0.offset] }
                if members.isEmpty { continue }
                var newCentroid = [Double](repeating: 0, count: d)
                for m in members {
                    for j in 0..<d { newCentroid[j] += m[j] }
                }
                let count = Double(members.count)
                centroids[c] = newCentroid.map { $0 / count }
            }
        }

        return (assignments, centroids)
    }

    private func silhouetteScore(data: [[Double]], assignments: [Int], k: Int) -> Double {
        guard data.count > k else { return 0 }
        var scores: [Double] = []

        for i in 0..<data.count {
            let cluster = assignments[i]
            let same = assignments.enumerated().filter { $0.element == cluster && $0.offset != i }
            let a: Double
            if same.isEmpty {
                a = 0
            } else {
                a = same.map { cosineDistance(data[i], data[$0.offset]) }.reduce(0, +) / Double(same.count)
            }

            var minB = Double.infinity
            for c in 0..<k where c != cluster {
                let others = assignments.enumerated().filter { $0.element == c }
                guard !others.isEmpty else { continue }
                let b = others.map { cosineDistance(data[i], data[$0.offset]) }.reduce(0, +) / Double(others.count)
                minB = min(minB, b)
            }

            if minB == .infinity { continue }
            let s = (minB - a) / max(a, minB)
            scores.append(s)
        }

        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
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
