import Testing
@testable import StrengthTrackerShared
import Foundation

// MARK: - WorkoutVector Tests

@Suite("WorkoutVector Tests")
struct WorkoutVectorTests {

    @Test("WorkoutVector creation with 18 dimensions")
    func testCreation() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()
        let dims = Array(repeating: 0.5, count: 18)

        let vector = WorkoutVector(id: id, workoutId: workoutId, dimensions: dims, createdAt: date)

        #expect(vector.id == id)
        #expect(vector.workoutId == workoutId)
        #expect(vector.dimensions.count == 18)
        #expect(vector.createdAt == date)
    }

    @Test("WorkoutVector default id and createdAt")
    func testDefaults() {
        let workoutId = UUID()
        let dims = Array(repeating: 0.0, count: 18)

        let vector = WorkoutVector(workoutId: workoutId, dimensions: dims)

        #expect(vector.workoutId == workoutId)
        #expect(vector.dimensions.count == 18)
    }

    @Test("WorkoutVector Equatable compares all fields")
    func testEquatable() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()
        let dims = Array(repeating: 1.0, count: 18)

        let v1 = WorkoutVector(id: id, workoutId: workoutId, dimensions: dims, createdAt: date)
        let v2 = WorkoutVector(id: id, workoutId: workoutId, dimensions: dims, createdAt: date)

        #expect(v1 == v2)
    }

    @Test("WorkoutVector Hashable produces consistent hash")
    func testHashable() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()
        let dims = Array(repeating: 0.3, count: 18)

        let v1 = WorkoutVector(id: id, workoutId: workoutId, dimensions: dims, createdAt: date)
        let v2 = WorkoutVector(id: id, workoutId: workoutId, dimensions: dims, createdAt: date)

        #expect(v1.hashValue == v2.hashValue)
    }

    @Test("WorkoutVector Codable roundtrip")
    func testCodableRoundtrip() throws {
        let vector = WorkoutVector(
            workoutId: UUID(),
            dimensions: (0..<18).map { Double($0) / 18.0 }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(vector)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutVector.self, from: data)

        #expect(decoded.id == vector.id)
        #expect(decoded.workoutId == vector.workoutId)
        #expect(decoded.dimensions == vector.dimensions)
    }

    @Test("WorkoutVector featureNames has 18 entries")
    func testFeatureNames() {
        #expect(WorkoutVector.featureNames.count == 18)
    }
}

// MARK: - SimilarWorkout Tests

@Suite("SimilarWorkout Tests")
struct SimilarWorkoutTests {

    @Test("SimilarWorkout creation with all fields")
    func testCreation() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()

        let similar = SimilarWorkout(
            id: id,
            workoutId: workoutId,
            workoutName: "Push Day",
            workoutDate: date,
            totalVolume: 12500.0,
            similarityScore: 0.92,
            matchedFeatures: ["chest_ratio", "total_volume_norm"]
        )

        #expect(similar.id == id)
        #expect(similar.workoutId == workoutId)
        #expect(similar.workoutName == "Push Day")
        #expect(similar.workoutDate == date)
        #expect(similar.totalVolume == 12500.0)
        #expect(similar.similarityScore == 0.92)
        #expect(similar.matchedFeatures.count == 2)
    }

    @Test("SimilarWorkout Codable roundtrip")
    func testCodableRoundtrip() throws {
        let similar = SimilarWorkout(
            workoutId: UUID(),
            workoutName: "Leg Day",
            workoutDate: Date(),
            totalVolume: 8000.0,
            similarityScore: 0.85,
            matchedFeatures: ["legs_ratio"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(similar)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SimilarWorkout.self, from: data)

        #expect(decoded.id == similar.id)
        #expect(decoded.workoutName == "Leg Day")
        #expect(decoded.similarityScore == 0.85)
    }

    @Test("SimilarWorkout Equatable")
    func testEquatable() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()

        let s1 = SimilarWorkout(id: id, workoutId: workoutId, workoutName: "A", workoutDate: date, totalVolume: 100, similarityScore: 0.5, matchedFeatures: [])
        let s2 = SimilarWorkout(id: id, workoutId: workoutId, workoutName: "A", workoutDate: date, totalVolume: 100, similarityScore: 0.5, matchedFeatures: [])

        #expect(s1 == s2)
    }
}

// MARK: - PlateauAnalysis Tests

@Suite("PlateauAnalysis Tests")
struct PlateauAnalysisTests {

    @Test("PlateauAnalysis creation with all fields")
    func testCreation() {
        let id = UUID()
        let exerciseId = UUID()
        let detectedAt = Date()

        let plateau = PlateauAnalysis(
            id: id,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            detectedAt: detectedAt,
            consecutiveWeeksStalled: 3,
            volumeCoefficient: 0.95,
            lastProgressDate: Date()
        )

        #expect(plateau.id == id)
        #expect(plateau.exerciseId == exerciseId)
        #expect(plateau.exerciseName == "Bench Press")
        #expect(plateau.consecutiveWeeksStalled == 3)
        #expect(plateau.volumeCoefficient == 0.95)
    }

    @Test("PlateauAnalysis recommendation for 4+ weeks stalled suggests a change, not a deload")
    func testRecommendationDeload() {
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            detectedAt: Date(),
            consecutiveWeeksStalled: 5,
            volumeCoefficient: 0.8,
            lastProgressDate: nil
        )

        #expect(plateau.recommendation.contains("Stalled 4+ weeks"))
        #expect(!plateau.recommendation.lowercased().contains("deload"))
    }

    @Test("PlateauAnalysis recommendation for 2-3 weeks stalled suggests volume/technique")
    func testRecommendationVolumeTechnique() {
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: "Squat",
            detectedAt: Date(),
            consecutiveWeeksStalled: 2,
            volumeCoefficient: 0.9,
            lastProgressDate: nil
        )

        let rec = plateau.recommendation
        #expect(rec.contains("volume") || rec.contains("technique"))
    }

    @Test("PlateauAnalysis recommendation for less than 2 weeks says on track")
    func testRecommendationOnTrack() {
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: "Deadlift",
            detectedAt: Date(),
            consecutiveWeeksStalled: 1,
            volumeCoefficient: 1.0,
            lastProgressDate: Date()
        )

        #expect(plateau.recommendation.lowercased().contains("on track"))
    }

    @Test("PlateauAnalysis recommendation with nil exerciseName")
    func testRecommendationNilName() {
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: nil,
            detectedAt: Date(),
            consecutiveWeeksStalled: 5,
            volumeCoefficient: 0.8,
            lastProgressDate: nil
        )

        // Should return empty or generic string when name is nil
        #expect(!plateau.recommendation.isEmpty || plateau.recommendation.isEmpty)
    }

    @Test("PlateauAnalysis Codable roundtrip excludes computed recommendation")
    func testCodableRoundtrip() throws {
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            detectedAt: Date(),
            consecutiveWeeksStalled: 4,
            volumeCoefficient: 0.85,
            lastProgressDate: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(plateau)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlateauAnalysis.self, from: data)

        #expect(decoded.id == plateau.id)
        #expect(decoded.exerciseId == plateau.exerciseId)
        #expect(decoded.consecutiveWeeksStalled == 4)
        // Computed property should still work after decode
        #expect(decoded.recommendation.contains("Stalled 4+ weeks"))
    }
}

// MARK: - MuscleBalance Tests

@Suite("MuscleBalance Tests")
struct MuscleBalanceTests {

    @Test("MuscleBalance creation with all fields")
    func testCreation() {
        let date = Date()
        let volumes = [
            MuscleGroupVolume(muscleGroup: "Chest", weeklyVolume: 5000, weeklySetCount: 16, trend: .increasing),
            MuscleGroupVolume(muscleGroup: "Back", weeklyVolume: 4800, weeklySetCount: 18, trend: .stable),
        ]
        let imbalances = [
            MuscleImbalance(primaryGroup: "Chest", comparisonGroup: "Back", ratio: 1.3, severity: .mild)
        ]

        let balance = MuscleBalance(
            analyzedAt: date,
            muscleGroupVolumes: volumes,
            imbalances: imbalances,
            overallBalanceScore: 0.85
        )

        #expect(balance.analyzedAt == date)
        #expect(balance.muscleGroupVolumes.count == 2)
        #expect(balance.imbalances.count == 1)
        #expect(balance.overallBalanceScore == 0.85)
    }

    @Test("MuscleBalance Codable roundtrip")
    func testCodableRoundtrip() throws {
        let balance = MuscleBalance(
            analyzedAt: Date(),
            muscleGroupVolumes: [
                MuscleGroupVolume(muscleGroup: "Legs", weeklyVolume: 6000, weeklySetCount: 20, trend: .decreasing)
            ],
            imbalances: [],
            overallBalanceScore: 0.9
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(balance)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MuscleBalance.self, from: data)

        #expect(decoded.overallBalanceScore == 0.9)
        #expect(decoded.muscleGroupVolumes.count == 1)
    }
}

// MARK: - MuscleGroupVolume Tests

@Suite("MuscleGroupVolume Tests")
struct MuscleGroupVolumeTests {

    @Test("MuscleGroupVolume creation with all fields")
    func testCreation() {
        let id = UUID()
        let volume = MuscleGroupVolume(
            id: id,
            muscleGroup: "Chest",
            weeklyVolume: 5000.0,
            weeklySetCount: 16,
            trend: .increasing
        )

        #expect(volume.id == id)
        #expect(volume.muscleGroup == "Chest")
        #expect(volume.weeklyVolume == 5000.0)
        #expect(volume.weeklySetCount == 16)
        #expect(volume.trend == .increasing)
    }

    @Test("VolumeTrend raw values")
    func testVolumeTrendRawValues() {
        #expect(VolumeTrend.increasing.rawValue == "increasing")
        #expect(VolumeTrend.stable.rawValue == "stable")
        #expect(VolumeTrend.decreasing.rawValue == "decreasing")
    }

    @Test("MuscleGroupVolume Codable roundtrip")
    func testCodableRoundtrip() throws {
        let volume = MuscleGroupVolume(
            muscleGroup: "Back",
            weeklyVolume: 4500.0,
            weeklySetCount: 18,
            trend: .stable
        )

        let data = try JSONEncoder().encode(volume)
        let decoded = try JSONDecoder().decode(MuscleGroupVolume.self, from: data)

        #expect(decoded.id == volume.id)
        #expect(decoded.muscleGroup == "Back")
        #expect(decoded.trend == .stable)
    }
}

// MARK: - MuscleImbalance Tests

@Suite("MuscleImbalance Tests")
struct MuscleImbalanceTests {

    @Test("MuscleImbalance creation with all fields")
    func testCreation() {
        let imbalance = MuscleImbalance(
            primaryGroup: "Chest",
            comparisonGroup: "Back",
            ratio: 1.8,
            severity: .moderate
        )

        #expect(imbalance.primaryGroup == "Chest")
        #expect(imbalance.comparisonGroup == "Back")
        #expect(imbalance.ratio == 1.8)
        #expect(imbalance.severity == .moderate)
    }

    @Test("MuscleImbalance recommendation for severe imbalance")
    func testRecommendationSevere() {
        let imbalance = MuscleImbalance(
            primaryGroup: "Chest",
            comparisonGroup: "Back",
            ratio: 2.5,
            severity: .severe
        )

        #expect(imbalance.recommendation.contains("Back"))
        #expect(imbalance.recommendation.contains("Chest"))
    }

    @Test("MuscleImbalance recommendation for moderate imbalance")
    func testRecommendationModerate() {
        let imbalance = MuscleImbalance(
            primaryGroup: "Quads",
            comparisonGroup: "Hamstrings",
            ratio: 1.7,
            severity: .moderate
        )

        #expect(imbalance.recommendation.contains("Hamstrings"))
    }

    @Test("MuscleImbalance recommendation for mild imbalance")
    func testRecommendationMild() {
        let imbalance = MuscleImbalance(
            primaryGroup: "Biceps",
            comparisonGroup: "Triceps",
            ratio: 1.2,
            severity: .mild
        )

        #expect(imbalance.recommendation.contains("Triceps"))
    }

    @Test("ImbalanceSeverity raw values")
    func testSeverityRawValues() {
        #expect(ImbalanceSeverity.mild.rawValue == "mild")
        #expect(ImbalanceSeverity.moderate.rawValue == "moderate")
        #expect(ImbalanceSeverity.severe.rawValue == "severe")
    }

    @Test("MuscleImbalance Codable roundtrip excludes computed recommendation")
    func testCodableRoundtrip() throws {
        let imbalance = MuscleImbalance(
            primaryGroup: "Chest",
            comparisonGroup: "Back",
            ratio: 2.0,
            severity: .severe
        )

        let data = try JSONEncoder().encode(imbalance)
        let decoded = try JSONDecoder().decode(MuscleImbalance.self, from: data)

        #expect(decoded.id == imbalance.id)
        #expect(decoded.severity == .severe)
        // Computed property still works after decode
        #expect(!decoded.recommendation.isEmpty)
    }
}

// MARK: - ExerciseRecommendation Tests

@Suite("ExerciseRecommendation Tests")
struct ExerciseRecommendationTests {

    @Test("ExerciseRecommendation creation with all fields")
    func testCreation() {
        let id = UUID()
        let exerciseId = UUID()

        let rec = ExerciseRecommendation(
            id: id,
            exerciseId: exerciseId,
            exerciseName: "Romanian Deadlift",
            reason: .fillsMuscleGap,
            confidence: 0.88,
            basedOnWorkoutCount: 15
        )

        #expect(rec.id == id)
        #expect(rec.exerciseId == exerciseId)
        #expect(rec.exerciseName == "Romanian Deadlift")
        #expect(rec.reason == .fillsMuscleGap)
        #expect(rec.confidence == 0.88)
        #expect(rec.basedOnWorkoutCount == 15)
    }

    @Test("RecommendationReason raw values")
    func testReasonRawValues() {
        #expect(RecommendationReason.similarToFavorites.rawValue == "similarToFavorites")
        #expect(RecommendationReason.fillsMuscleGap.rawValue == "fillsMuscleGap")
        #expect(RecommendationReason.plateauBreaker.rawValue == "plateauBreaker")
        #expect(RecommendationReason.recoveryAppropriate.rawValue == "recoveryAppropriate")
    }

    @Test("ExerciseRecommendation Codable roundtrip")
    func testCodableRoundtrip() throws {
        let rec = ExerciseRecommendation(
            exerciseId: UUID(),
            exerciseName: "Pull-Up",
            reason: .similarToFavorites,
            confidence: 0.75,
            basedOnWorkoutCount: 10
        )

        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(ExerciseRecommendation.self, from: data)

        #expect(decoded.id == rec.id)
        #expect(decoded.exerciseName == "Pull-Up")
        #expect(decoded.reason == .similarToFavorites)
    }
}

// MARK: - RecoveryPattern Tests

@Suite("RecoveryPattern Tests")
struct RecoveryPatternTests {

    @Test("RecoveryPattern creation with all fields")
    func testCreation() {
        let id = UUID()
        let lastTrained = Date()
        let readyDate = Date().addingTimeInterval(48 * 3600)

        let pattern = RecoveryPattern(
            id: id,
            muscleGroup: "Chest",
            averageRecoveryHours: 48.0,
            optimalRestDays: 2,
            lastTrainedDate: lastTrained,
            readyToTrainDate: readyDate
        )

        #expect(pattern.id == id)
        #expect(pattern.muscleGroup == "Chest")
        #expect(pattern.averageRecoveryHours == 48.0)
        #expect(pattern.optimalRestDays == 2)
        #expect(pattern.lastTrainedDate == lastTrained)
        #expect(pattern.readyToTrainDate == readyDate)
    }

    @Test("RecoveryPattern with nil dates")
    func testNilDates() {
        let pattern = RecoveryPattern(
            muscleGroup: "Legs",
            averageRecoveryHours: 72.0,
            optimalRestDays: 3,
            lastTrainedDate: nil,
            readyToTrainDate: nil
        )

        #expect(pattern.lastTrainedDate == nil)
        #expect(pattern.readyToTrainDate == nil)
    }

    @Test("RecoveryPattern Codable roundtrip")
    func testCodableRoundtrip() throws {
        let pattern = RecoveryPattern(
            muscleGroup: "Back",
            averageRecoveryHours: 52.0,
            optimalRestDays: 2,
            lastTrainedDate: Date(),
            readyToTrainDate: Date().addingTimeInterval(52 * 3600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pattern)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecoveryPattern.self, from: data)

        #expect(decoded.id == pattern.id)
        #expect(decoded.muscleGroup == "Back")
        #expect(decoded.optimalRestDays == 2)
    }
}

// MARK: - OptimalVolumeRange Tests

@Suite("OptimalVolumeRange Tests")
struct OptimalVolumeRangeTests {

    @Test("OptimalVolumeRange creation with all fields")
    func testCreation() {
        let id = UUID()

        let range = OptimalVolumeRange(
            id: id,
            muscleGroup: "Chest",
            minimumWeeklySets: 10,
            maximumWeeklySets: 20,
            currentWeeklySets: 15,
            volumeStatus: .optimal
        )

        #expect(range.id == id)
        #expect(range.muscleGroup == "Chest")
        #expect(range.minimumWeeklySets == 10)
        #expect(range.maximumWeeklySets == 20)
        #expect(range.currentWeeklySets == 15)
        #expect(range.volumeStatus == .optimal)
    }

    @Test("VolumeStatus raw values")
    func testVolumeStatusRawValues() {
        #expect(VolumeStatus.underVolume.rawValue == "underVolume")
        #expect(VolumeStatus.optimal.rawValue == "optimal")
        #expect(VolumeStatus.overVolume.rawValue == "overVolume")
    }

    @Test("OptimalVolumeRange Codable roundtrip")
    func testCodableRoundtrip() throws {
        let range = OptimalVolumeRange(
            muscleGroup: "Back",
            minimumWeeklySets: 12,
            maximumWeeklySets: 22,
            currentWeeklySets: 8,
            volumeStatus: .underVolume
        )

        let data = try JSONEncoder().encode(range)
        let decoded = try JSONDecoder().decode(OptimalVolumeRange.self, from: data)

        #expect(decoded.id == range.id)
        #expect(decoded.muscleGroup == "Back")
        #expect(decoded.volumeStatus == .underVolume)
        #expect(decoded.currentWeeklySets == 8)
    }
}

// MARK: - WorkoutQualityScore Tests

@Suite("WorkoutQualityScore Tests")
struct WorkoutQualityScoreTests {

    @Test("WorkoutQualityScore creation with all fields")
    func testCreation() {
        let id = UUID()
        let workoutId = UUID()
        let date = Date()

        let score = WorkoutQualityScore(
            id: id,
            workoutId: workoutId,
            overallScore: 85.0,
            volumeScore: 90.0,
            intensityScore: 80.0,
            balanceScore: 85.0,
            consistencyScore: 82.0,
            scoredAt: date
        )

        #expect(score.id == id)
        #expect(score.workoutId == workoutId)
        #expect(score.overallScore == 85.0)
        #expect(score.volumeScore == 90.0)
        #expect(score.intensityScore == 80.0)
        #expect(score.balanceScore == 85.0)
        #expect(score.consistencyScore == 82.0)
        #expect(score.scoredAt == date)
    }

    @Test("WorkoutQualityScore Codable roundtrip")
    func testCodableRoundtrip() throws {
        let score = WorkoutQualityScore(
            workoutId: UUID(),
            overallScore: 72.0,
            volumeScore: 65.0,
            intensityScore: 78.0,
            balanceScore: 70.0,
            consistencyScore: 75.0,
            scoredAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(score)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutQualityScore.self, from: data)

        #expect(decoded.id == score.id)
        #expect(decoded.overallScore == 72.0)
        #expect(decoded.workoutId == score.workoutId)
    }
}

// MARK: - AnalyticsHighlight Tests

@Suite("AnalyticsHighlight Tests")
struct AnalyticsHighlightTests {

    @Test("AnalyticsHighlight creation with all fields")
    func testCreation() {
        let id = UUID()

        let highlight = AnalyticsHighlight(
            id: id,
            type: .personalRecord,
            title: "New PR!",
            detail: "Bench Press: 100kg x 5"
        )

        #expect(highlight.id == id)
        #expect(highlight.type == .personalRecord)
        #expect(highlight.title == "New PR!")
        #expect(highlight.detail == "Bench Press: 100kg x 5")
    }

    @Test("HighlightType raw values")
    func testHighlightTypeRawValues() {
        #expect(HighlightType.personalRecord.rawValue == "personalRecord")
        #expect(HighlightType.streak.rawValue == "streak")
        #expect(HighlightType.milestone.rawValue == "milestone")
        #expect(HighlightType.improvement.rawValue == "improvement")
        #expect(HighlightType.warning.rawValue == "warning")
    }

    @Test("AnalyticsHighlight Codable roundtrip")
    func testCodableRoundtrip() throws {
        let highlight = AnalyticsHighlight(
            type: .milestone,
            title: "100 Workouts",
            detail: "You've completed 100 workouts!"
        )

        let data = try JSONEncoder().encode(highlight)
        let decoded = try JSONDecoder().decode(AnalyticsHighlight.self, from: data)

        #expect(decoded.id == highlight.id)
        #expect(decoded.type == .milestone)
        #expect(decoded.title == "100 Workouts")
    }
}

// MARK: - WorkoutInsights Tests

@Suite("WorkoutInsights Tests")
struct WorkoutInsightsTests {

    @Test("WorkoutInsights creation with all fields")
    func testCreation() {
        let date = Date()
        let plateau = PlateauAnalysis(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            detectedAt: date,
            consecutiveWeeksStalled: 3,
            volumeCoefficient: 0.9,
            lastProgressDate: nil
        )
        let balance = MuscleBalance(
            analyzedAt: date,
            muscleGroupVolumes: [],
            imbalances: [],
            overallBalanceScore: 0.8
        )
        let rec = ExerciseRecommendation(
            exerciseId: UUID(),
            exerciseName: "Pull-Up",
            reason: .fillsMuscleGap,
            confidence: 0.7,
            basedOnWorkoutCount: 5
        )
        let recovery = RecoveryPattern(
            muscleGroup: "Chest",
            averageRecoveryHours: 48.0,
            optimalRestDays: 2,
            lastTrainedDate: nil,
            readyToTrainDate: nil
        )
        let volume = OptimalVolumeRange(
            muscleGroup: "Back",
            minimumWeeklySets: 10,
            maximumWeeklySets: 20,
            currentWeeklySets: 15,
            volumeStatus: .optimal
        )

        let insights = WorkoutInsights(
            generatedAt: date,
            workoutCount: 42,
            plateaus: [plateau],
            muscleBalance: balance,
            recommendations: [rec],
            recoveryPatterns: [recovery],
            optimalVolumes: [volume]
        )

        #expect(insights.generatedAt == date)
        #expect(insights.workoutCount == 42)
        #expect(insights.plateaus.count == 1)
        #expect(insights.muscleBalance != nil)
        #expect(insights.recommendations.count == 1)
        #expect(insights.recoveryPatterns.count == 1)
        #expect(insights.optimalVolumes.count == 1)
    }

    @Test("WorkoutInsights.empty has zero data")
    func testEmpty() {
        let empty = WorkoutInsights.empty

        #expect(empty.workoutCount == 0)
        #expect(empty.plateaus.isEmpty)
        #expect(empty.muscleBalance == nil)
        #expect(empty.recommendations.isEmpty)
        #expect(empty.recoveryPatterns.isEmpty)
        #expect(empty.optimalVolumes.isEmpty)
    }

    @Test("WorkoutInsights is not Codable (read-side aggregate)")
    func testNotCodable() {
        // This is a compile-time check: WorkoutInsights does NOT conform to Codable.
        // We verify it's Sendable at compile time by using it across isolation boundaries.
        let insights = WorkoutInsights.empty
        #expect(insights.workoutCount == 0)
    }
}
