# Vector-Based Workout Analytics Architecture

**Project**: StrengthTracker iOS App
**Version**: 1.0
**Date**: 2026-02-16
**Author**: System Architecture Designer

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Domain Model Extensions](#2-domain-model-extensions)
3. [Service Layer Design](#3-service-layer-design)
4. [Data Flow](#4-data-flow)
5. [Repository Layer](#5-repository-layer)
6. [ViewModel Layer](#6-viewmodel-layer)
7. [Vectorization Strategy](#7-vectorization-strategy)
8. [Performance Design](#8-performance-design)
9. [Testing Strategy](#9-testing-strategy)
10. [Migration & Rollout](#10-migration--rollout)
11. [Future Extensions](#11-future-extensions)

---

## 1. System Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SwiftUI Views Layer                          │
│  (DashboardView, WorkoutAnalyticsView, ExerciseRecommendationsView) │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│                       ViewModel Layer (@Observable)                  │
│    ┌──────────────────────────────────────────────────────────┐    │
│    │  WorkoutAnalyticsViewModel                                │    │
│    │  - Similar workouts, plateau detection, muscle balance    │    │
│    │  - Exercise recommendations, recovery patterns            │    │
│    └─────────────────────────┬────────────────────────────────┘    │
└──────────────────────────────┼─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                         Service Layer                                │
│  ┌──────────────────┐  ┌────────────────────┐  ┌─────────────────┐│
│  │ WorkoutAnalytics │  │ VectorSearchService│  │ WorkoutVectorizer││
│  │    Service       │  │  (Accelerate vDSP) │  │ (Feature Extract)││
│  └────────┬─────────┘  └──────────┬─────────┘  └────────┬────────┘│
│           │                       │                      │          │
│  ┌────────▼─────────┐  ┌─────────▼───────┐   ┌─────────▼────────┐│
│  │ PlateauDetection │  │ MuscleBalance   │   │ ExerciseRecommend││
│  │    Service       │  │    Service      │   │   -ationService  ││
│  └──────────────────┘  └─────────────────┘   └──────────────────┘│
└──────────────────────────────┬─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                      Repository Layer                                │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  AnalyticsRepository (Protocol)                              │  │
│  │  - Store/retrieve vectors, compute similarities              │  │
│  │  - Fetch workouts by date range, muscle group                │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                              │                                       │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │  SwiftDataAnalyticsRepository (Implementation)               │  │
│  │  - Uses WorkoutRepository for workout data                   │  │
│  │  - Manages WorkoutVectorEntity lifecycle                     │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
└──────────────────────────────┼─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│                    SwiftData Persistence Layer                       │
│  ┌─────────────────┐  ┌──────────────────────┐  ┌───────────────┐ │
│  │ WorkoutEntity   │  │ WorkoutVectorEntity  │  │ ExerciseEntity│ │
│  │ (existing)      │──│ (NEW - 72 bytes)     │  │ (existing)    │ │
│  └─────────────────┘  └──────────────────────┘  └───────────────┘ │
│                            @Relationship                             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         AppContainer (DI)                            │
│  - Initializes all repositories, services, ViewModels               │
│  - Single source of truth for dependencies                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Integration Points

**Existing Components Used:**
- `/workspaces/strength_tracker/StrengthTracker/Shared/DI/AppContainer.swift` - Add analytics services
- `/workspaces/strength_tracker/StrengthTracker/Shared/Repositories/Protocols/WorkoutRepository.swift` - Workout data access
- `/workspaces/strength_tracker/StrengthTracker/Shared/Persistence/SwiftData/Entities/WorkoutEntity.swift` - Extended with vector relationship
- `/workspaces/strength_tracker/StrengthTracker/Shared/Models/Domain/Workout.swift` - Domain model (unchanged)
- `/workspaces/strength_tracker/StrengthTracker/Shared/Models/Domain/Enums.swift` - MuscleGroup, ExerciseType enums

**New Components:**
- `Shared/Models/Domain/Analytics/` - New domain models for analytics
- `Shared/Services/Analytics/` - Analytics service layer
- `Shared/Repositories/Protocols/AnalyticsRepository.swift` - Analytics repository protocol
- `Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift` - Vector storage
- `Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift` - Repository implementation
- `Shared/ViewModels/WorkoutAnalyticsViewModel.swift` - Analytics ViewModel
- `iOS/Features/Analytics/` - Analytics UI views

### 1.3 Navigation Strategy

**Decision: Keep existing 5-tab TabView. Analytics is a pushed screen, not a tab.**

The existing 5 tabs (Dashboard, Workout, Templates, Exercises, History) serve core transactional workflows. Analytics is exploratory and accessed via contextual entry points using push navigation (`NavigationLink` / `.sheet`):

| Entry Point | Navigation | Target Screen |
|-------------|------------|---------------|
| Dashboard → Insights Card → "View All" | `NavigationLink` push | `WorkoutAnalyticsView` (full dashboard) |
| Dashboard → Insights Card → tap card | `.sheet` | Insight detail (plateau, balance, etc.) |
| Post-Workout Sheet → "View Similar" | `.sheet` | `SimilarWorkoutsView` |
| History → Workout Detail → "Similar" | `NavigationLink` push | `SimilarWorkoutsView` |
| Exercises → Exercise Detail → Insights tab | In-place tab | Plateau detection, recommendations |

This keeps `ContentView.swift` unchanged (5 tabs) and follows Apple HIG guidance (max 5 tabs on iPhone).

---

## 2. Domain Model Extensions

### 2.1 Core Analytics Domain Models

**File: `Shared/Models/Domain/Analytics/WorkoutVector.swift`**

```swift
import Foundation

/// A feature vector representing a workout's characteristics
/// - 18 dimensions capturing volume, intensity, muscle distribution, progression
/// - L2 normalized for cosine similarity computation
public struct WorkoutVector: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID // Same as workout ID
    public let workoutId: UUID
    public let createdAt: Date
    public let dimensions: [Double] // 18 elements, L2 normalized

    /// Human-readable feature names for debugging
    public static let featureNames: [String] = [
        "total_volume_norm",        // 0: Total volume (normalized 0-1)
        "avg_weight_norm",          // 1: Average weight across all sets
        "avg_reps_norm",            // 2: Average reps across all sets
        "set_count_norm",           // 3: Total number of sets
        "exercise_diversity",       // 4: Number of unique exercises / max observed
        "duration_norm",            // 5: Workout duration (0-1)
        "chest_ratio",              // 6: % volume on chest
        "back_ratio",               // 7: % volume on back
        "legs_ratio",               // 8: % volume on legs (quads+hams+glutes+calves)
        "shoulders_ratio",          // 9: % volume on shoulders
        "arms_ratio",               // 10: % volume on arms (biceps+triceps)
        "core_ratio",               // 11: % volume on core
        "compound_ratio",           // 12: % of barbell/compound exercises
        "avg_rpe",                  // 13: Average RPE (0-10 scale, 0-1 normalized)
        "volume_vs_prev_7d",        // 14: % change vs 7-day moving average
        "volume_vs_prev_30d",       // 15: % change vs 30-day moving average
        "pr_count_norm",            // 16: Number of PRs in workout (normalized)
        "time_of_day_sin",          // 17: Cyclic encoding of workout time (sin component)
    ]

    public init(
        id: UUID,
        workoutId: UUID,
        createdAt: Date,
        dimensions: [Double]
    ) {
        precondition(dimensions.count == 18, "WorkoutVector must have exactly 18 dimensions")
        self.id = id
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.dimensions = dimensions
    }
}
```

**File: `Shared/Models/Domain/Analytics/SimilarWorkout.swift`**

```swift
import Foundation

/// A reference to a similar workout with its similarity score.
/// References the workout by ID only (DDD: cross-aggregate references by identity).
/// The presentation layer resolves the full Workout when needed for display.
public struct SimilarWorkout: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let workoutId: UUID
    public let workoutName: String // Denormalized for display without fetching
    public let workoutDate: Date   // Denormalized for display without fetching
    public let totalVolume: Double  // Denormalized for display without fetching
    public let similarityScore: Double // 0.0 to 1.0 (cosine similarity)
    public let matchedFeatures: [String] // Top 3 matching feature names

    public init(
        id: UUID,
        workoutId: UUID,
        workoutName: String,
        workoutDate: Date,
        totalVolume: Double,
        similarityScore: Double,
        matchedFeatures: [String]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.workoutDate = workoutDate
        self.totalVolume = totalVolume
        self.similarityScore = similarityScore
        self.matchedFeatures = matchedFeatures
    }
}
```

**File: `Shared/Models/Domain/Analytics/PlateauAnalysis.swift`**

```swift
import Foundation

/// Analysis of progress plateau for an exercise or muscle group.
/// Recommendation text is a computed property derived from the model's own data
/// (DDD: domain model owns its business rules, services produce data not presentation).
public struct PlateauAnalysis: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exerciseId: UUID?
    public let exerciseName: String?
    public let muscleGroup: MuscleGroup?
    public let plateauDetected: Bool
    public let consecutiveWeeksStalled: Int
    public let averageVolumePerWeek: Double
    public let volumeStdDev: Double
    public let lastImprovement: Date?
    public let confidenceScore: Double // 0.0 to 1.0

    /// Business rule: recommendation derived from analysis data
    public var recommendation: String {
        guard let name = exerciseName else { return "" }
        if consecutiveWeeksStalled >= 4 {
            return "Consider deloading \(name) by 10-20% and focus on form, or try a variation."
        } else if consecutiveWeeksStalled >= 2 {
            return "Try increasing volume by 5-10% or adding a technique like drop sets for \(name)."
        } else {
            return "Progress is on track for \(name). Keep pushing!"
        }
    }

    public init(
        id: UUID,
        exerciseId: UUID?,
        exerciseName: String?,
        muscleGroup: MuscleGroup?,
        plateauDetected: Bool,
        consecutiveWeeksStalled: Int,
        averageVolumePerWeek: Double,
        volumeStdDev: Double,
        lastImprovement: Date?,
        confidenceScore: Double
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.plateauDetected = plateauDetected
        self.consecutiveWeeksStalled = consecutiveWeeksStalled
        self.averageVolumePerWeek = averageVolumePerWeek
        self.volumeStdDev = volumeStdDev
        self.lastImprovement = lastImprovement
        self.confidenceScore = confidenceScore
    }
}
```

**File: `Shared/Models/Domain/Analytics/MuscleBalance.swift`**

```swift
import Foundation

/// Analysis of muscle group balance and training distribution
public struct MuscleBalance: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let analyzedDate: Date
    public let muscleGroupVolumes: [MuscleGroup: Double] // Total volume per muscle group
    public let muscleGroupPercentages: [MuscleGroup: Double] // Percentage of total
    public let imbalances: [MuscleImbalance]
    public let overallScore: Double // 0.0 to 1.0 (1.0 = perfectly balanced)

    public init(
        id: UUID,
        analyzedDate: Date,
        muscleGroupVolumes: [MuscleGroup: Double],
        muscleGroupPercentages: [MuscleGroup: Double],
        imbalances: [MuscleImbalance],
        overallScore: Double
    ) {
        self.id = id
        self.analyzedDate = analyzedDate
        self.muscleGroupVolumes = muscleGroupVolumes
        self.muscleGroupPercentages = muscleGroupPercentages
        self.imbalances = imbalances
        self.overallScore = overallScore
    }
}

public struct MuscleImbalance: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let primaryGroup: MuscleGroup
    public let comparisonGroup: MuscleGroup
    public let ratio: Double // e.g., 2.5 means primary is 2.5x comparison
    public let severity: ImbalanceSeverity

    /// Business rule: recommendation derived from imbalance data
    public var recommendation: String {
        let ratioStr = String(format: "%.1f", ratio)
        switch severity {
        case .severe:
            return "Significantly reduce \(primaryGroup.rawValue) volume and increase \(comparisonGroup.rawValue) by 30-40% (\(ratioStr)x imbalance)."
        case .moderate:
            return "Increase \(comparisonGroup.rawValue) volume by 20-30% to balance \(primaryGroup.rawValue) training (\(ratioStr)x imbalance)."
        case .mild:
            return "Consider adding 1-2 more sets for \(comparisonGroup.rawValue) to improve balance with \(primaryGroup.rawValue) (\(ratioStr)x imbalance)."
        }
    }

    public init(
        id: UUID,
        primaryGroup: MuscleGroup,
        comparisonGroup: MuscleGroup,
        ratio: Double,
        severity: ImbalanceSeverity
    ) {
        self.id = id
        self.primaryGroup = primaryGroup
        self.comparisonGroup = comparisonGroup
        self.ratio = ratio
        self.severity = severity
    }
}

public enum ImbalanceSeverity: String, Codable, Sendable {
    case mild       // 1.0 - 1.5x
    case moderate   // 1.5 - 2.0x
    case severe     // 2.0x+
}
```

**File: `Shared/Models/Domain/Analytics/ExerciseRecommendation.swift`**

```swift
import Foundation

/// A recommended exercise based on training history and gaps
public struct ExerciseRecommendation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    public let recommendationReason: RecommendationReason
    public let confidenceScore: Double // 0.0 to 1.0
    public let targetMuscleGroups: [MuscleGroup]
    public let estimatedVolume: Double? // Suggested starting volume
    public let basedOnSimilarWorkouts: [UUID] // Workout IDs used for recommendation

    public init(
        id: UUID,
        exercise: Exercise,
        recommendationReason: RecommendationReason,
        confidenceScore: Double,
        targetMuscleGroups: [MuscleGroup],
        estimatedVolume: Double?,
        basedOnSimilarWorkouts: [UUID]
    ) {
        self.id = id
        self.exercise = exercise
        self.recommendationReason = recommendationReason
        self.confidenceScore = confidenceScore
        self.targetMuscleGroups = targetMuscleGroups
        self.estimatedVolume = estimatedVolume
        self.basedOnSimilarWorkouts = basedOnSimilarWorkouts
    }
}

public enum RecommendationReason: String, Codable, Sendable {
    case muscleImbalance    // To correct volume imbalance
    case plateauBreaker     // Alternative to stalled exercise
    case progressionPattern // Based on successful progression history
    case complementary      // Complements current training split
    case recovery           // Lower intensity for recovery
}
```

**File: `Shared/Models/Domain/Analytics/RecoveryPattern.swift`**

```swift
import Foundation

/// Analysis of optimal recovery time between muscle group training
public struct RecoveryPattern: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let muscleGroup: MuscleGroup
    public let optimalRestDays: Double // Average optimal rest days
    public let minRestDays: Int
    public let maxRestDays: Int
    public let sampleSize: Int // Number of workout pairs analyzed
    public let correlationWithPerformance: Double // -1.0 to 1.0

    public init(
        id: UUID,
        muscleGroup: MuscleGroup,
        optimalRestDays: Double,
        minRestDays: Int,
        maxRestDays: Int,
        sampleSize: Int,
        correlationWithPerformance: Double
    ) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.optimalRestDays = optimalRestDays
        self.minRestDays = minRestDays
        self.maxRestDays = maxRestDays
        self.sampleSize = sampleSize
        self.correlationWithPerformance = correlationWithPerformance
    }
}
```

**File: `Shared/Models/Domain/Analytics/OptimalVolumeRange.swift`**

```swift
import Foundation

/// Optimal volume range for an exercise based on performance correlation
public struct OptimalVolumeRange: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exerciseId: UUID
    public let exerciseName: String
    public let optimalMinVolume: Double
    public let optimalMaxVolume: Double
    public let currentVolume: Double?
    public let progressCorrelation: Double // Correlation between volume and progress
    public let sampleSize: Int
    public let recommendation: String

    public init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String,
        optimalMinVolume: Double,
        optimalMaxVolume: Double,
        currentVolume: Double?,
        progressCorrelation: Double,
        sampleSize: Int,
        recommendation: String
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.optimalMinVolume = optimalMinVolume
        self.optimalMaxVolume = optimalMaxVolume
        self.currentVolume = currentVolume
        self.progressCorrelation = progressCorrelation
        self.sampleSize = sampleSize
        self.recommendation = recommendation
    }
}
```

**File: `Shared/Models/Domain/Analytics/WorkoutQualityScore.swift`**

```swift
import Foundation

/// Post-workout quality score shown on the workout completion sheet.
/// Scores 0-100 based on volume, intensity, balance, and rest quality.
/// Aligned with UX post-workout sheet wireframe.
public struct WorkoutQualityScore: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let workoutId: UUID
    public let overallScore: Int // 0-100
    public let starRating: Int // 1-5 (derived: score/20 clamped)
    public let volumeRating: QualityRating
    public let intensityRating: QualityRating
    public let restTimesRating: QualityRating
    public let balanceRating: QualityRating
    public let highlights: [WorkoutHighlight]

    public init(
        id: UUID,
        workoutId: UUID,
        overallScore: Int,
        starRating: Int,
        volumeRating: QualityRating,
        intensityRating: QualityRating,
        restTimesRating: QualityRating,
        balanceRating: QualityRating,
        highlights: [WorkoutHighlight]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.overallScore = overallScore
        self.starRating = starRating
        self.volumeRating = volumeRating
        self.intensityRating = intensityRating
        self.restTimesRating = restTimesRating
        self.balanceRating = balanceRating
        self.highlights = highlights
    }
}

public enum QualityRating: String, Codable, Sendable {
    case optimal    // Green checkmark
    case good       // Green checkmark
    case warning    // Yellow warning
    case low        // Orange alert
}

public struct WorkoutHighlight: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: HighlightType
    public let title: String
    public let detail: String

    public init(id: UUID, type: HighlightType, title: String, detail: String) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
    }
}

public enum HighlightType: String, Codable, Sendable {
    case personalRecord  // "New PR! Bench Press: 85kg x 5"
    case volumeRecord    // "Highest volume leg day ever"
    case consistency     // "5th workout this week"
    case improvement     // "+2.5kg from last week"
}
```

### 2.2 Analytics Aggregate: WorkoutInsights

The analytics domain models above are read projections — they're computed from workout data, not independently persisted entities. In DDD terms, they form a **read-side aggregate** rooted at `WorkoutInsights`, which groups all analytics results for a dashboard load. This prevents the ViewModel from holding 6+ independent arrays and provides a single consistency boundary for analytics state.

**File: `Shared/Models/Domain/Analytics/WorkoutInsights.swift`**

```swift
import Foundation

/// Aggregate root for analytics read projections.
/// Groups all computed insights for a single analytics load,
/// ensuring consistent state (all insights from the same data snapshot).
public struct WorkoutInsights: Sendable {
    public let generatedAt: Date
    public let workoutCount: Int // Number of workouts in the analysis window

    // Read projections (nil = not yet loaded or insufficient data)
    public let plateaus: [PlateauAnalysis]
    public let muscleBalance: MuscleBalance?
    public let recommendations: [ExerciseRecommendation]
    public let recoveryPatterns: [RecoveryPattern]
    public let optimalVolumes: [OptimalVolumeRange]

    public init(
        generatedAt: Date,
        workoutCount: Int,
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange]
    ) {
        self.generatedAt = generatedAt
        self.workoutCount = workoutCount
        self.plateaus = plateaus
        self.muscleBalance = muscleBalance
        self.recommendations = recommendations
        self.recoveryPatterns = recoveryPatterns
        self.optimalVolumes = optimalVolumes
    }

    /// Empty insights (for initial state before data loads)
    public static let empty = WorkoutInsights(
        generatedAt: Date(),
        workoutCount: 0,
        plateaus: [],
        muscleBalance: nil,
        recommendations: [],
        recoveryPatterns: [],
        optimalVolumes: []
    )
}
```

> **DDD Note:** `SimilarWorkout` and `WorkoutQualityScore` are scoped to a single workout (not the dashboard), so they live outside this aggregate — they're returned by dedicated service methods when the user views a specific workout.

### 2.3 SwiftData Entity Extension

**File: `Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift`**

```swift
#if canImport(SwiftData)
import SwiftData
import Foundation

/// SwiftData entity storing the 18-dimensional feature vector for a workout
/// - 72 bytes for vector data (18 * Float32 = 72 bytes)
/// - Optimized for linear scan similarity search (<5ms for 2000 workouts)
@Model
public final class WorkoutVectorEntity {
    @Attribute(.unique) public var id: UUID
    public var workoutId: UUID
    public var createdAt: Date

    // Vector storage: 18 Float32 values stored as Data (72 bytes)
    // Using Float32 instead of Double64 to save 50% space (72 bytes vs 144 bytes)
    @Attribute(.externalStorage) public var vectorData: Data

    // Denormalized fields for faster querying without JOIN
    public var totalVolume: Double
    public var workoutDate: Date
    public var primaryMuscleGroups: [String] // Top 3 muscle groups by volume

    public init(
        id: UUID,
        workoutId: UUID,
        createdAt: Date,
        vectorData: Data,
        totalVolume: Double,
        workoutDate: Date,
        primaryMuscleGroups: [String]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.vectorData = vectorData
        self.totalVolume = totalVolume
        self.workoutDate = workoutDate
        self.primaryMuscleGroups = primaryMuscleGroups
    }

    /// Convert Data back to [Float]
    public func getVector() -> [Float] {
        vectorData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
#endif
```

**Extended `WorkoutEntity` (add to existing file):**

```swift
// Add to Shared/Persistence/SwiftData/Entities/WorkoutEntity.swift
// After line 16 (exercises relationship):

    @Relationship(deleteRule: .cascade)
    public var workoutVector: WorkoutVectorEntity?
```

### 2.4 WorkoutVectorMapper

Follows the existing codebase pattern (`WorkoutMapper`, `ExerciseMapper`, `TemplateMapper`, `PersonalRecordMapper`) — a dedicated mapper translating between SwiftData entities and domain models, including the Float32↔Double conversion at the repository boundary (ADR-002).

**File: `Shared/Persistence/Mappers/WorkoutVectorMapper.swift`**

```swift
import Foundation

/// Maps between WorkoutVectorEntity (persistence) and WorkoutVector (domain).
/// Handles Float32↔Double conversion at the repository boundary (ADR-002).
public enum WorkoutVectorMapper {

    // MARK: - Entity → Domain

    public static func toDomain(_ entity: WorkoutVectorEntity) -> WorkoutVector {
        WorkoutVector(
            id: entity.id,
            workoutId: entity.workoutId,
            createdAt: entity.createdAt,
            dimensions: dataToDoubles(entity.vectorData)
        )
    }

    // MARK: - Domain → Entity

    public static func toEntity(_ domain: WorkoutVector, totalVolume: Double, workoutDate: Date, primaryMuscleGroups: [String]) -> WorkoutVectorEntity {
        WorkoutVectorEntity(
            id: domain.id,
            workoutId: domain.workoutId,
            createdAt: domain.createdAt,
            vectorData: doublesToData(domain.dimensions),
            totalVolume: totalVolume,
            workoutDate: workoutDate,
            primaryMuscleGroups: primaryMuscleGroups
        )
    }

    // MARK: - Float32↔Double Conversion (ADR-002)

    /// Convert [Double] domain values to Float32 Data for storage (72 bytes)
    public static func doublesToData(_ dimensions: [Double]) -> Data {
        let floats = dimensions.map { Float($0) }
        return Data(bytes: floats, count: floats.count * MemoryLayout<Float>.stride)
    }

    /// Convert Float32 Data back to [Double] domain values
    public static func dataToDoubles(_ data: Data) -> [Double] {
        let floats = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        return floats.map { Double($0) }
    }
}
```

---

## 3. Service Layer Design

### 3.1 WorkoutVectorizer Service

**File: `Shared/Services/Analytics/WorkoutVectorizer.swift`**

```swift
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Extracts 18-dimensional feature vectors from workout data.
/// Stateless service (DDD: services should not hold mutable state).
/// Historical context is passed as a parameter, not stored.
/// - Feature engineering optimized for similarity search
/// - L2 normalization for cosine similarity
@MainActor
public final class WorkoutVectorizer: Sendable {

    // MARK: - Normalization Constants (learned from data)
    private let maxVolume: Double = 50000.0      // 99th percentile
    private let maxWeight: Double = 300.0        // 99th percentile (kg)
    private let maxReps: Int = 30                // 99th percentile
    private let maxSets: Int = 100               // 99th percentile
    private let maxExercises: Int = 15           // 99th percentile
    private let maxDuration: TimeInterval = 7200 // 2 hours
    private let maxPRs: Int = 10                 // 99th percentile

    public init() {}

    /// Extract feature vector from a workout
    /// - Parameters:
    ///   - workout: The workout to vectorize
    ///   - historicalWorkouts: Recent workouts for computing relative features (7d/30d averages)
    public func vectorize(_ workout: Workout, historicalWorkouts: [Workout] = []) -> WorkoutVector {
        var features = [Double](repeating: 0.0, count: 18)

        // 0: Total volume (normalized)
        features[0] = min(workout.totalVolume / maxVolume, 1.0)

        // 1: Average weight across all sets
        let allSets = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }
        let avgWeight = allSets.compactMap(\.weight).reduce(0, +) / Double(max(allSets.count, 1))
        features[1] = min(avgWeight / maxWeight, 1.0)

        // 2: Average reps
        let avgReps = allSets.compactMap(\.reps).reduce(0, +) / max(allSets.count, 1)
        features[2] = Double(avgReps) / Double(maxReps)

        // 3: Set count (normalized)
        features[3] = Double(allSets.count) / Double(maxSets)

        // 4: Exercise diversity
        let uniqueExercises = Set(workout.exercises.map { $0.exercise.id }).count
        features[4] = Double(uniqueExercises) / Double(maxExercises)

        // 5: Duration (normalized)
        if let duration = workout.duration {
            features[5] = min(duration / maxDuration, 1.0)
        }

        // 6-11: Muscle group ratios (percentage of total volume)
        let muscleVolumes = calculateMuscleGroupVolumes(workout)
        let totalVol = workout.totalVolume > 0 ? workout.totalVolume : 1.0
        features[6] = muscleVolumes[.chest] ?? 0.0 / totalVol      // chest
        features[7] = muscleVolumes[.back] ?? 0.0 / totalVol       // back
        let legsVol = (muscleVolumes[.quadriceps] ?? 0.0) + (muscleVolumes[.hamstrings] ?? 0.0) +
                      (muscleVolumes[.glutes] ?? 0.0) + (muscleVolumes[.calves] ?? 0.0)
        features[8] = legsVol / totalVol                            // legs
        features[9] = muscleVolumes[.shoulders] ?? 0.0 / totalVol  // shoulders
        let armsVol = (muscleVolumes[.biceps] ?? 0.0) + (muscleVolumes[.triceps] ?? 0.0)
        features[10] = armsVol / totalVol                           // arms
        features[11] = muscleVolumes[.core] ?? 0.0 / totalVol      // core

        // 12: Compound exercise ratio (barbell exercises)
        let compoundCount = workout.exercises.filter { $0.exercise.category == .barbell }.count
        features[12] = Double(compoundCount) / Double(max(workout.exercises.count, 1))

        // 13: Average RPE (0-10 scale, normalized to 0-1)
        let avgRPE = allSets.compactMap(\.rpe).reduce(0, +) / Double(max(allSets.count, 1))
        features[13] = avgRPE / 10.0

        // 14-15: Volume vs historical moving averages
        let (vol7d, vol30d) = calculateHistoricalVolumes(workout, historicalWorkouts: historicalWorkouts)
        features[14] = vol7d
        features[15] = vol30d

        // 16: PR count (normalized)
        let prCount = allSets.filter(\.isPersonalRecord).count
        features[16] = Double(prCount) / Double(maxPRs)

        // 17: Time of day (sin encoding for cyclical feature)
        let hour = Calendar.current.component(.hour, from: workout.startedAt)
        features[17] = sin(Double(hour) * 2.0 * .pi / 24.0) * 0.5 + 0.5 // Normalize to 0-1

        // L2 normalization for cosine similarity
        let normalized = l2Normalize(features)

        return WorkoutVector(
            id: UUID(),
            workoutId: workout.id,
            createdAt: Date(),
            dimensions: normalized
        )
    }

    // MARK: - Helper Methods

    private func calculateMuscleGroupVolumes(_ workout: Workout) -> [MuscleGroup: Double] {
        var volumes: [MuscleGroup: Double] = [:]

        for exercise in workout.exercises {
            let exerciseVolume = exercise.exerciseVolume

            // Primary muscle gets 70% of volume
            volumes[exercise.exercise.primaryMuscleGroup, default: 0] += exerciseVolume * 0.7

            // Secondary muscles split remaining 30%
            let secondaryShare = exerciseVolume * 0.3 / Double(max(exercise.exercise.secondaryMuscleGroups.count, 1))
            for secondary in exercise.exercise.secondaryMuscleGroups {
                volumes[secondary, default: 0] += secondaryShare
            }
        }

        return volumes
    }

    private func calculateHistoricalVolumes(_ workout: Workout, historicalWorkouts: [Workout]) -> (vol7d: Double, vol30d: Double) {
        let calendar = Calendar.current
        let workoutDate = workout.startedAt

        // 7-day moving average (excluding current workout)
        let last7Days = historicalWorkouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            let daysDiff = calendar.dateComponents([.day], from: completedAt, to: workoutDate).day ?? 0
            return daysDiff >= 0 && daysDiff <= 7 && $0.id != workout.id
        }
        let avg7d = last7Days.map(\.totalVolume).reduce(0, +) / Double(max(last7Days.count, 1))
        let change7d = avg7d > 0 ? (workout.totalVolume - avg7d) / avg7d : 0.0

        // 30-day moving average
        let last30Days = historicalWorkouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            let daysDiff = calendar.dateComponents([.day], from: completedAt, to: workoutDate).day ?? 0
            return daysDiff >= 0 && daysDiff <= 30 && $0.id != workout.id
        }
        let avg30d = last30Days.map(\.totalVolume).reduce(0, +) / Double(max(last30Days.count, 1))
        let change30d = avg30d > 0 ? (workout.totalVolume - avg30d) / avg30d : 0.0

        // Clamp to [-1, 1] range
        return (
            vol7d: max(-1.0, min(1.0, change7d)),
            vol30d: max(-1.0, min(1.0, change30d))
        )
    }

    private func l2Normalize(_ vector: [Double]) -> [Double] {
        #if canImport(Accelerate)
        var result = vector
        var magnitude: Double = 0.0
        vDSP_dotprD(vector, 1, vector, 1, &magnitude, vDSP_Length(vector.count))
        magnitude = sqrt(magnitude)

        if magnitude > 0 {
            var divisor = magnitude
            vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        }
        return result
        #else
        // Fallback for Linux tests
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
        #endif
    }
}
```

### 3.2 VectorSearchService

**File: `Shared/Services/Analytics/VectorSearchService.swift`**

```swift
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// High-performance vector similarity search using Apple Accelerate
/// - Linear scan with vDSP optimized dot product (<5ms for 2000 vectors)
/// - Cosine similarity: dot(A, B) since vectors are L2 normalized
@MainActor
public final class VectorSearchService: Sendable {

    public init() {}

    /// Find k most similar vectors to query
    /// - Returns: Array of (index, similarity) tuples sorted by similarity descending
    public func findSimilar(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        #if canImport(Accelerate)
        return findSimilarAccelerate(query: query, vectors: vectors, topK: topK)
        #else
        return findSimilarFallback(query: query, vectors: vectors, topK: topK)
        #endif
    }

    /// Compute cosine similarity between two L2-normalized vectors
    public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0.0 }

        #if canImport(Accelerate)
        var result: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
        #else
        return zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        #endif
    }

    /// Batch compute similarities for all vectors
    /// - Optimized with BLAS operations
    public func batchSimilarities(
        query: [Double],
        vectors: [[Double]]
    ) -> [Double] {
        #if canImport(Accelerate)
        return vectors.map { vector in
            var result: Double = 0.0
            vDSP_dotprD(query, 1, vector, 1, &result, vDSP_Length(query.count))
            return result
        }
        #else
        return vectors.map { vector in
            zip(query, vector).reduce(0.0) { $0 + $1.0 * $1.1 }
        }
        #endif
    }

    // MARK: - Private Accelerate Implementation

    #if canImport(Accelerate)
    private func findSimilarAccelerate(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        // Compute all similarities in batch
        let similarities = batchSimilarities(query: query, vectors: vectors)

        // Create indexed array and sort by similarity descending
        let indexed = similarities.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { $0.1 > $1.1 }

        // Return top K
        return Array(sorted.prefix(topK))
    }
    #endif

    // MARK: - Fallback Implementation (Linux tests)

    private func findSimilarFallback(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        let similarities = vectors.enumerated().map { (index, vector) in
            let similarity = zip(query, vector).reduce(0.0) { $0 + $1.0 * $1.1 }
            return (index, similarity)
        }

        return Array(similarities.sorted { $0.1 > $1.1 }.prefix(topK))
    }
}
```

### 3.3 WorkoutAnalyticsService (Orchestrator)

**File: `Shared/Services/Analytics/WorkoutAnalyticsService.swift`**

```swift
import Foundation

/// High-level orchestrator for all analytics operations
/// - Coordinates between vectorizer, search, and domain-specific services
/// - Caches frequently accessed data
@MainActor
public final class WorkoutAnalyticsService: Sendable {

    private let analyticsRepository: any AnalyticsRepository
    private let workoutRepository: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let vectorizer: WorkoutVectorizer
    private let searchService: VectorSearchService
    private let plateauService: PlateauDetectionService
    private let muscleBalanceService: MuscleBalanceService
    private let recommendationService: ExerciseRecommendationService

    // Cache
    private var cachedVectors: [UUID: WorkoutVector] = [:]
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    public init(
        analyticsRepository: any AnalyticsRepository,
        workoutRepository: any WorkoutRepository,
        exerciseRepository: any ExerciseRepository,
        vectorizer: WorkoutVectorizer,
        searchService: VectorSearchService,
        plateauService: PlateauDetectionService,
        muscleBalanceService: MuscleBalanceService,
        recommendationService: ExerciseRecommendationService
    ) {
        self.analyticsRepository = analyticsRepository
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.vectorizer = vectorizer
        self.searchService = searchService
        self.plateauService = plateauService
        self.muscleBalanceService = muscleBalanceService
        self.recommendationService = recommendationService
    }

    // MARK: - Similar Workouts

    /// Find workouts similar to the given workout
    public func findSimilarWorkouts(
        to workout: Workout,
        limit: Int = 5,
        minSimilarity: Double = 0.7
    ) async throws -> [SimilarWorkout] {
        // Ensure workout is vectorized
        try await ensureVectorized(workout)

        // Get all vectors
        let allVectors = try await analyticsRepository.fetchAllVectors()
        let queryVector = allVectors.first { $0.workoutId == workout.id }

        guard let queryVector = queryVector else {
            throw AnalyticsError.vectorNotFound
        }

        // Search for similar vectors
        let vectors = allVectors.filter { $0.workoutId != workout.id }
        let similarities = searchService.findSimilar(
            query: queryVector.dimensions,
            vectors: vectors.map(\.dimensions),
            topK: limit * 2 // Get more, then filter by threshold
        )

        // Filter by minimum similarity and map to domain
        let filtered = similarities.filter { $0.similarity >= minSimilarity }
        let topResults = Array(filtered.prefix(limit))

        // Fetch corresponding workouts (via WorkoutRepository, not AnalyticsRepository)
        let workoutIds = topResults.map { vectors[$0.index].workoutId }
        let workouts = try await workoutRepository.fetchByIds(workoutIds)

        // Map to SimilarWorkout domain models (ID reference, not embedded Workout)
        return try topResults.compactMap { result in
            guard let workout = workouts.first(where: { $0.id == vectors[result.index].workoutId }) else {
                return nil
            }

            let matchedFeatures = identifyTopMatchedFeatures(
                query: queryVector.dimensions,
                match: vectors[result.index].dimensions,
                topK: 3
            )

            return SimilarWorkout(
                id: UUID(),
                workoutId: workout.id,
                workoutName: workout.name ?? "Workout",
                workoutDate: workout.startedAt,
                totalVolume: workout.totalVolume,
                similarityScore: result.similarity,
                matchedFeatures: matchedFeatures
            )
        }
    }

    // MARK: - Dashboard Aggregate

    /// Generate a consistent WorkoutInsights snapshot for the dashboard
    public func generateInsights(timeWindow: TimeInterval = 2_592_000) async throws -> WorkoutInsights {
        let workouts = try await workoutRepository.fetchAll()

        // Run analyses concurrently from the same data snapshot
        async let plateausResult = plateauService.analyzePlateaus(workouts: workouts, timeWindow: timeWindow)
        let muscleBalanceResult = muscleBalanceService.analyze(workouts: workouts, timeWindow: timeWindow)

        return WorkoutInsights(
            generatedAt: Date(),
            workoutCount: workouts.count,
            plateaus: (try? await plateausResult) ?? [],
            muscleBalance: muscleBalanceResult,
            recommendations: [],       // Loaded on-demand per workout
            recoveryPatterns: [],       // Future extension
            optimalVolumes: []          // Future extension
        )
    }

    // MARK: - Plateau Detection

    public func detectPlateaus(timeWindow: TimeInterval = 2_592_000) async throws -> [PlateauAnalysis] {
        let workouts = try await workoutRepository.fetchAll()
        return try await plateauService.analyzePlateaus(workouts: workouts, timeWindow: timeWindow)
    }

    // MARK: - Muscle Balance

    public func analyzeMuscleBalance(timeWindow: TimeInterval = 2_592_000) async throws -> MuscleBalance {
        let workouts = try await workoutRepository.fetchAll()
        return muscleBalanceService.analyze(workouts: workouts, timeWindow: timeWindow)
    }

    // MARK: - Exercise Recommendations

    public func generateRecommendations(for workout: Workout, limit: Int = 5) async throws -> [ExerciseRecommendation] {
        let allWorkouts = try await workoutRepository.fetchAll()
        let allExercises = try await exerciseRepository.fetchAll()
        let muscleBalance = muscleBalanceService.analyze(workouts: allWorkouts, timeWindow: 2_592_000)

        return try await recommendationService.recommend(
            for: workout,
            allWorkouts: allWorkouts,
            availableExercises: allExercises,
            muscleBalance: muscleBalance,
            limit: limit
        )
    }

    // MARK: - Vectorization Management

    /// Ensure a workout has been vectorized
    public func ensureVectorized(_ workout: Workout) async throws {
        let existing = try await analyticsRepository.fetchVector(for: workout.id)
        if existing == nil {
            try await vectorizeWorkout(workout)
        }
    }

    /// Vectorize a single workout and store
    public func vectorizeWorkout(_ workout: Workout) async throws {
        // Fetch historical workouts for context-aware feature scaling
        let allWorkouts = try await workoutRepository.fetchAll()

        // Generate vector (stateless — context passed as parameter)
        let vector = vectorizer.vectorize(workout, historicalWorkouts: allWorkouts)

        // Store
        try await analyticsRepository.storeVector(vector)

        // Update cache
        cachedVectors[workout.id] = vector
    }

    /// Batch vectorize all workouts missing vectors
    public func vectorizeAllWorkouts() async throws {
        let allWorkouts = try await workoutRepository.fetchAll()
        let existingVectors = try await analyticsRepository.fetchAllVectors()
        let vectorizedIds = Set(existingVectors.map(\.workoutId))

        let needsVectorization = allWorkouts.filter { !vectorizedIds.contains($0.id) }

        // Vectorize in batch (pass full history for context-aware scaling)
        for workout in needsVectorization {
            let vector = vectorizer.vectorize(workout, historicalWorkouts: allWorkouts)
            try await analyticsRepository.storeVector(vector)
        }

        // Invalidate cache
        cachedVectors.removeAll()
        cacheTimestamp = nil
    }

    // MARK: - Helpers

    private func identifyTopMatchedFeatures(
        query: [Double],
        match: [Double],
        topK: Int
    ) -> [String] {
        let differences = zip(query, match).map { abs($0 - $1) }
        let indexed = differences.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { $0.1 < $1.1 } // Smallest difference = best match

        return sorted.prefix(topK).map { WorkoutVector.featureNames[$0.0] }
    }
}

public enum AnalyticsError: Error {
    case vectorNotFound
    case insufficientData
    case invalidTimeWindow
}
```

### 3.4 PlateauDetectionService

**File: `Shared/Services/Analytics/PlateauDetectionService.swift`**

```swift
import Foundation

/// Detects progress plateaus using statistical analysis
/// - Sliding window volume analysis
/// - Coefficient of variation (CV) for stagnation detection
@MainActor
public final class PlateauDetectionService: Sendable {

    private let minWeeksForAnalysis = 4
    private let plateauThresholdCV = 0.10 // <10% CV indicates plateau
    private let minImprovementThreshold = 1.05 // 5% volume increase

    public init() {}

    /// Analyze plateaus across all exercises and muscle groups
    public func analyzePlateaus(
        workouts: [Workout],
        timeWindow: TimeInterval
    ) async throws -> [PlateauAnalysis] {
        let cutoffDate = Date().addingTimeInterval(-timeWindow)
        let recentWorkouts = workouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            return completedAt >= cutoffDate
        }

        guard recentWorkouts.count >= minWeeksForAnalysis else {
            throw AnalyticsError.insufficientData
        }

        var analyses: [PlateauAnalysis] = []

        // Analyze per exercise
        let exerciseGroups = Dictionary(grouping: recentWorkouts.flatMap { workout in
            workout.exercises.map { (workout, $0) }
        }) { $0.1.exercise.id }

        for (exerciseId, workoutExercises) in exerciseGroups {
            guard workoutExercises.count >= minWeeksForAnalysis else { continue }

            let analysis = analyzeExercisePlateau(
                exerciseId: exerciseId,
                exerciseName: workoutExercises.first!.1.exercise.name,
                workoutExercises: workoutExercises
            )
            analyses.append(analysis)
        }

        return analyses.sorted { $0.consecutiveWeeksStalled > $1.consecutiveWeeksStalled }
    }

    private func analyzeExercisePlateau(
        exerciseId: UUID,
        exerciseName: String,
        workoutExercises: [(Workout, WorkoutExercise)]
    ) -> PlateauAnalysis {
        // Sort by workout date
        let sorted = workoutExercises.sorted { $0.0.startedAt < $1.0.startedAt }

        // Calculate weekly volumes
        let weeklyVolumes = grouped(sorted, byWeeks: 1).map { group in
            group.reduce(0.0) { $0 + $1.1.exerciseVolume }
        }

        // Calculate statistics
        let avgVolume = weeklyVolumes.reduce(0, +) / Double(weeklyVolumes.count)
        let stdDev = calculateStdDev(weeklyVolumes, mean: avgVolume)
        let cv = stdDev / avgVolume // Coefficient of variation

        // Detect consecutive weeks without improvement
        var weeksStalled = 0
        var lastImprovement: Date? = nil

        for i in 1..<weeklyVolumes.count {
            if weeklyVolumes[i] >= weeklyVolumes[i-1] * minImprovementThreshold {
                lastImprovement = sorted[i].0.startedAt
                weeksStalled = 0
            } else {
                weeksStalled += 1
            }
        }

        let plateauDetected = cv < plateauThresholdCV && weeksStalled >= 2

        // Note: recommendation is a computed property on PlateauAnalysis (DDD: domain owns its rules)
        return PlateauAnalysis(
            id: UUID(),
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            muscleGroup: nil,
            plateauDetected: plateauDetected,
            consecutiveWeeksStalled: weeksStalled,
            averageVolumePerWeek: avgVolume,
            volumeStdDev: stdDev,
            lastImprovement: lastImprovement,
            confidenceScore: min(Double(weeklyVolumes.count) / 8.0, 1.0) // More weeks = higher confidence
        )
    }

    private func grouped(_ items: [(Workout, WorkoutExercise)], byWeeks weeks: Int) -> [[(Workout, WorkoutExercise)]] {
        let calendar = Calendar.current
        var groups: [Date: [(Workout, WorkoutExercise)]] = [:]

        for item in items {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: item.0.startedAt)!.start
            groups[weekStart, default: []].append(item)
        }

        return groups.values.sorted { $0.first!.0.startedAt < $1.first!.0.startedAt }
    }

    private func calculateStdDev(_ values: [Double], mean: Double) -> Double {
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
```

### 3.5 MuscleBalanceService

**File: `Shared/Services/Analytics/MuscleBalanceService.swift`**

```swift
import Foundation

/// Analyzes muscle group balance and identifies volume imbalances
@MainActor
public final class MuscleBalanceService: Sendable {

    // Antagonist pairs for balance analysis
    private let antagonistPairs: [(MuscleGroup, MuscleGroup)] = [
        (.chest, .back),
        (.quadriceps, .hamstrings),
        (.biceps, .triceps)
    ]

    // Thresholds
    private let mildImbalanceThreshold = 1.5
    private let moderateImbalanceThreshold = 2.0

    public init() {}

    /// Analyze muscle balance from workout history
    public func analyze(workouts: [Workout], timeWindow: TimeInterval) -> MuscleBalance {
        let cutoffDate = Date().addingTimeInterval(-timeWindow)
        let recentWorkouts = workouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            return completedAt >= cutoffDate
        }

        // Calculate total volume per muscle group
        var muscleVolumes: [MuscleGroup: Double] = [:]

        for workout in recentWorkouts {
            for exercise in workout.exercises {
                let volume = exercise.exerciseVolume

                // Primary muscle gets 70%
                muscleVolumes[exercise.exercise.primaryMuscleGroup, default: 0] += volume * 0.7

                // Secondary muscles split 30%
                let secondaryShare = volume * 0.3 / Double(max(exercise.exercise.secondaryMuscleGroups.count, 1))
                for secondary in exercise.exercise.secondaryMuscleGroups {
                    muscleVolumes[secondary, default: 0] += secondaryShare
                }
            }
        }

        // Calculate percentages
        let totalVolume = muscleVolumes.values.reduce(0, +)
        let musclePercentages = muscleVolumes.mapValues { $0 / totalVolume }

        // Identify imbalances
        let imbalances = identifyImbalances(muscleVolumes: muscleVolumes)

        // Calculate overall balance score (0-1, 1 = perfect)
        let overallScore = calculateBalanceScore(imbalances: imbalances)

        return MuscleBalance(
            id: UUID(),
            analyzedDate: Date(),
            muscleGroupVolumes: muscleVolumes,
            muscleGroupPercentages: musclePercentages,
            imbalances: imbalances,
            overallScore: overallScore
        )
    }

    private func identifyImbalances(muscleVolumes: [MuscleGroup: Double]) -> [MuscleImbalance] {
        var imbalances: [MuscleImbalance] = []

        for (primary, comparison) in antagonistPairs {
            let primaryVol = muscleVolumes[primary] ?? 0
            let comparisonVol = muscleVolumes[comparison] ?? 0

            guard primaryVol > 0 && comparisonVol > 0 else { continue }

            let ratio = primaryVol / comparisonVol

            // Note: recommendation is a computed property on MuscleImbalance (DDD: domain owns its rules)
            if ratio >= mildImbalanceThreshold {
                let severity: ImbalanceSeverity = ratio >= moderateImbalanceThreshold ? .severe : .moderate

                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: primary,
                    comparisonGroup: comparison,
                    ratio: ratio,
                    severity: severity
                ))
            }

            // Check reverse imbalance
            let reverseRatio = comparisonVol / primaryVol
            if reverseRatio >= mildImbalanceThreshold {
                let severity: ImbalanceSeverity = reverseRatio >= moderateImbalanceThreshold ? .severe : .moderate

                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: comparison,
                    comparisonGroup: primary,
                    ratio: reverseRatio,
                    severity: severity
                ))
            }
        }

        return imbalances
    }

    private func calculateBalanceScore(imbalances: [MuscleImbalance]) -> Double {
        if imbalances.isEmpty {
            return 1.0
        }

        let severityPenalties: [ImbalanceSeverity: Double] = [
            .mild: 0.05,
            .moderate: 0.15,
            .severe: 0.30
        ]

        let totalPenalty = imbalances.reduce(0.0) { total, imbalance in
            total + (severityPenalties[imbalance.severity] ?? 0)
        }

        return max(0.0, 1.0 - totalPenalty)
    }
}
```

### 3.6 ExerciseRecommendationService

**File: `Shared/Services/Analytics/ExerciseRecommendationService.swift`**

```swift
import Foundation

/// Recommends exercises based on training history, plateaus, and muscle balance
@MainActor
public final class ExerciseRecommendationService: Sendable {

    public init() {}

    /// Generate exercise recommendations
    public func recommend(
        for workout: Workout,
        allWorkouts: [Workout],
        availableExercises: [Exercise],
        muscleBalance: MuscleBalance,
        limit: Int
    ) async throws -> [ExerciseRecommendation] {
        var recommendations: [ExerciseRecommendation] = []

        // 1. Muscle imbalance recommendations
        for imbalance in muscleBalance.imbalances.prefix(2) {
            let exercises = availableExercises.filter { exercise in
                exercise.primaryMuscleGroup == imbalance.comparisonGroup &&
                !workout.exercises.contains { $0.exercise.id == exercise.id }
            }

            if let exercise = exercises.first {
                recommendations.append(ExerciseRecommendation(
                    id: UUID(),
                    exercise: exercise,
                    recommendationReason: .muscleImbalance,
                    confidenceScore: 0.9,
                    targetMuscleGroups: [imbalance.comparisonGroup],
                    estimatedVolume: calculateEstimatedVolume(for: exercise, in: allWorkouts),
                    basedOnSimilarWorkouts: []
                ))
            }
        }

        // 2. Complementary exercises (fill gaps in current workout)
        let currentMuscles = Set(workout.exercises.map { $0.exercise.primaryMuscleGroup })
        let allMuscles: Set<MuscleGroup> = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .biceps, .triceps]
        let missingMuscles = allMuscles.subtracting(currentMuscles)

        for muscle in missingMuscles.prefix(2) {
            let exercises = availableExercises.filter { exercise in
                exercise.primaryMuscleGroup == muscle &&
                !workout.exercises.contains { $0.exercise.id == exercise.id }
            }

            if let exercise = exercises.first {
                recommendations.append(ExerciseRecommendation(
                    id: UUID(),
                    exercise: exercise,
                    recommendationReason: .complementary,
                    confidenceScore: 0.7,
                    targetMuscleGroups: [muscle],
                    estimatedVolume: calculateEstimatedVolume(for: exercise, in: allWorkouts),
                    basedOnSimilarWorkouts: []
                ))
            }
        }

        return Array(recommendations.prefix(limit))
    }

    private func calculateEstimatedVolume(for exercise: Exercise, in workouts: [Workout]) -> Double {
        let historicalVolumes = workouts.flatMap { workout in
            workout.exercises.filter { $0.exercise.id == exercise.id }.map { $0.exerciseVolume }
        }

        guard !historicalVolumes.isEmpty else { return 0 }

        return historicalVolumes.reduce(0, +) / Double(historicalVolumes.count)
    }
}
```

### 3.7 WorkoutQualityScoreService

**File: `Shared/Services/Analytics/WorkoutQualityScoreService.swift`**

```swift
import Foundation

/// Computes a post-workout quality score (0-100) shown on the completion sheet.
/// Evaluates volume, intensity, rest times, and muscle group balance relative
/// to the user's historical patterns.
///
/// Score breakdown (25 points each):
/// - Volume: Is total volume within the user's optimal range?
/// - Intensity: Is average weight/1RM ratio appropriate?
/// - Rest times: Were rest periods consistent and sufficient?
/// - Balance: Did the workout hit muscle groups proportionally?
@MainActor
public final class WorkoutQualityScoreService: Sendable {

    private let workoutRepository: any WorkoutRepository
    private let muscleBalanceService: MuscleBalanceService

    public init(
        workoutRepository: any WorkoutRepository,
        muscleBalanceService: MuscleBalanceService
    ) {
        self.workoutRepository = workoutRepository
        self.muscleBalanceService = muscleBalanceService
    }

    /// Compute quality score for a completed workout
    public func computeScore(for workout: Workout) async throws -> WorkoutQualityScore {
        let recentWorkouts = try await workoutRepository.fetchAll()

        // Volume score (0-25): compare to 4-week moving average
        let volumeScore = computeVolumeScore(workout, history: recentWorkouts)

        // Intensity score (0-25): RPE or weight/1RM within target
        let intensityScore = computeIntensityScore(workout)

        // Rest times score (0-25): consistency and sufficiency
        let restScore = computeRestTimesScore(workout)

        // Balance score (0-25): muscle group distribution
        let balanceScore = computeBalanceScore(workout, history: recentWorkouts)

        let overall = volumeScore.points + intensityScore.points +
                      restScore.points + balanceScore.points
        let stars = max(1, min(5, overall / 20))

        // Detect highlights (PRs, records, streaks)
        let highlights = detectHighlights(workout, history: recentWorkouts)

        return WorkoutQualityScore(
            id: UUID(),
            workoutId: workout.id,
            overallScore: overall,
            starRating: stars,
            volumeRating: volumeScore.rating,
            intensityRating: intensityScore.rating,
            restTimesRating: restScore.rating,
            balanceRating: balanceScore.rating,
            highlights: highlights
        )
    }

    // MARK: - Scoring Components

    private struct ComponentScore {
        let points: Int // 0-25
        let rating: QualityRating
    }

    private func computeVolumeScore(_ workout: Workout, history: [Workout]) -> ComponentScore {
        let avgVolume = history.suffix(12).map(\.totalVolume).reduce(0, +) /
                        Double(max(history.suffix(12).count, 1))

        guard avgVolume > 0 else { return ComponentScore(points: 20, rating: .good) }

        let ratio = workout.totalVolume / avgVolume
        switch ratio {
        case 0.8...1.2: return ComponentScore(points: 25, rating: .optimal)
        case 0.6...1.4: return ComponentScore(points: 20, rating: .good)
        case 0.4...1.6: return ComponentScore(points: 12, rating: .warning)
        default:        return ComponentScore(points: 5, rating: .low)
        }
    }

    private func computeIntensityScore(_ workout: Workout) -> ComponentScore {
        let sets = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }
        let rpes = sets.compactMap(\.rpe)

        guard !rpes.isEmpty else { return ComponentScore(points: 18, rating: .good) }

        let avgRPE = rpes.reduce(0, +) / Double(rpes.count)
        switch avgRPE {
        case 6.0...8.5: return ComponentScore(points: 25, rating: .optimal)
        case 5.0...9.0: return ComponentScore(points: 20, rating: .good)
        case 4.0...9.5: return ComponentScore(points: 12, rating: .warning)
        default:        return ComponentScore(points: 5, rating: .low)
        }
    }

    private func computeRestTimesScore(_ workout: Workout) -> ComponentScore {
        // Rest time scoring based on consistency
        // Without explicit rest tracking, give a good default score
        let duration = workout.duration ?? 0
        let setCount = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }.count

        guard setCount > 0, duration > 0 else {
            return ComponentScore(points: 18, rating: .good)
        }

        let avgTimePerSet = duration / Double(setCount) // seconds per set (includes rest)
        switch avgTimePerSet {
        case 60...180: return ComponentScore(points: 25, rating: .optimal)
        case 45...240: return ComponentScore(points: 20, rating: .good)
        case 30...300: return ComponentScore(points: 12, rating: .warning)
        default:       return ComponentScore(points: 5, rating: .low)
        }
    }

    private func computeBalanceScore(_ workout: Workout, history: [Workout]) -> ComponentScore {
        let balance = muscleBalanceService.analyze(
            workouts: [workout],
            timeWindow: 0 // Just this workout
        )

        switch balance.overallScore {
        case 0.8...1.0: return ComponentScore(points: 25, rating: .optimal)
        case 0.6...0.8: return ComponentScore(points: 20, rating: .good)
        case 0.4...0.6: return ComponentScore(points: 12, rating: .warning)
        default:        return ComponentScore(points: 5, rating: .low)
        }
    }

    private func detectHighlights(_ workout: Workout, history: [Workout]) -> [WorkoutHighlight] {
        var highlights: [WorkoutHighlight] = []

        // Check for PRs
        let prSets = workout.exercises.flatMap { $0.sets.filter(\.isPersonalRecord) }
        for prSet in prSets {
            highlights.append(WorkoutHighlight(
                id: UUID(),
                type: .personalRecord,
                title: "New PR!",
                detail: "\(prSet.weight ?? 0)kg x \(prSet.reps ?? 0)"
            ))
        }

        return highlights
    }
}
```

---

## 4. Data Flow

### 4.1 Vector Creation Flow

```
User completes workout
         │
         ▼
WorkoutViewModel.completeWorkout()
         │
         ▼
WorkoutRepository.complete(workoutId)
         │
         ▼
[POST-SAVE HOOK - Background Task]
         │
         ▼
WorkoutAnalyticsService.ensureVectorized(workout)
         │
         ├─► WorkoutVectorizer.vectorize(workout)
         │   ├─► Extract 18 features
         │   ├─► L2 normalize
         │   └─► Return WorkoutVector
         │
         └─► AnalyticsRepository.storeVector(vector)
             └─► Save WorkoutVectorEntity to SwiftData
```

### 4.2 Similar Workout Query Flow

```
User views workout detail
         │
         ▼
WorkoutAnalyticsViewModel.loadSimilarWorkouts(workout)
         │
         ▼
WorkoutAnalyticsService.findSimilarWorkouts(to: workout)
         │
         ├─► AnalyticsRepository.fetchAllVectors()
         │   └─► SwiftData fetch WorkoutVectorEntity
         │
         ├─► VectorSearchService.findSimilar(query, vectors, topK)
         │   └─► Accelerate vDSP dot products (bulk)
         │
         └─► WorkoutRepository.fetchByIds(ids)
             └─► Build [SimilarWorkout] with ID + denormalized display fields
```

### 4.3 Dashboard Insights Flow (Aggregate)

```
Dashboard loads
         │
         ▼
WorkoutAnalyticsViewModel.loadDashboardInsights()
         │
         ▼
WorkoutAnalyticsService.generateInsights()
         │
         ├─► detectPlateaus()
         │   └─► PlateauDetectionService.analyzePlateaus(workouts)
         │
         ├─► analyzeMuscleBalance()
         │   └─► MuscleBalanceService.analyzeBalance(workouts)
         │
         ├─► generateRecommendations()
         │   └─► ExerciseRecommendationService
         │
         └─► Return WorkoutInsights (single aggregate snapshot)
```

### 4.4 SwiftData Schema

```swift
// Extended schema in AppContainer.init()
let schema = Schema([
    ExerciseEntity.self,
    WorkoutEntity.self,
    WorkoutExerciseEntity.self,
    ExerciseSetEntity.self,
    WorkoutTemplateEntity.self,
    TemplateExerciseEntity.self,
    PersonalRecordEntity.self,
    WorkoutVectorEntity.self // NEW
])
```

**Relationships:**
- `WorkoutEntity.workoutVector` → `WorkoutVectorEntity` (1:1, cascade delete)
- `WorkoutVectorEntity.workoutId` → `WorkoutEntity.id` (FK, indexed)

---

## 5. Repository Layer

### 5.1 AnalyticsRepository Protocol

**File: `Shared/Repositories/Protocols/AnalyticsRepository.swift`**

```swift
import Foundation

/// Repository for WorkoutVectorEntity only (DDD: one repository per aggregate/entity type).
/// Workout queries belong on WorkoutRepository, not here.
@MainActor
public protocol AnalyticsRepository: Sendable {
    func storeVector(_ vector: WorkoutVector) async throws
    func fetchVector(for workoutId: UUID) async throws -> WorkoutVector?
    func fetchAllVectors() async throws -> [WorkoutVector]
    func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector]
    func deleteVector(for workoutId: UUID) async throws
}
```

> **DDD Note:** Workout queries (`fetchWorkoutsByIds`, `fetchByDateRange`, etc.) stay on `WorkoutRepository`. The `WorkoutAnalyticsService` orchestrator holds references to both `AnalyticsRepository` and `WorkoutRepository` and coordinates between them. This matches how existing services use `WorkoutRepository` and `ExerciseRepository` — repositories are never mixed.

### 5.2 SwiftDataAnalyticsRepository

**File: `Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift`**

```swift
#if canImport(SwiftData)
import SwiftData
import Foundation

/// Manages WorkoutVectorEntity only. Uses WorkoutVectorMapper for entity↔domain conversion.
/// Workout queries are handled by WorkoutRepository (DDD: single-entity repository).
@MainActor
public final class SwiftDataAnalyticsRepository: AnalyticsRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Vector CRUD

    public func storeVector(_ vector: WorkoutVector) async throws {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == vector.workoutId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.vectorData = WorkoutVectorMapper.doublesToData(vector.dimensions)
            existing.createdAt = vector.createdAt
        } else {
            let entity = WorkoutVectorMapper.toEntity(
                vector,
                totalVolume: 0,
                workoutDate: vector.createdAt,
                primaryMuscleGroups: []
            )
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    public func fetchVector(for workoutId: UUID) async throws -> WorkoutVector? {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        guard let entity = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return WorkoutVectorMapper.toDomain(entity)
    }

    public func fetchAllVectors() async throws -> [WorkoutVector] {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { WorkoutVectorMapper.toDomain($0) }
    }

    public func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector] {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { entity in
                entity.workoutDate >= start && entity.workoutDate <= end
            },
            sortBy: [SortDescriptor(\.workoutDate, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { WorkoutVectorMapper.toDomain($0) }
    }

    public func deleteVector(for workoutId: UUID) async throws {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
#endif
```

---

## 6. ViewModel Layer

### 6.1 WorkoutAnalyticsViewModel

**File: `Shared/ViewModels/WorkoutAnalyticsViewModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class WorkoutAnalyticsViewModel {

    // MARK: - Published State

    /// Dashboard aggregate — loaded as a consistent snapshot
    public var insights: WorkoutInsights = .empty
    public var isInsightsLoading = false

    /// Per-workout results (loaded on demand, outside the aggregate)
    public var similarWorkouts: [SimilarWorkout] = []
    public var isSimilarWorkoutsLoading = false

    public var qualityScore: WorkoutQualityScore?
    public var isQualityScoreLoading = false

    /// Feature gating
    public var nextFeatureUnlock: (feature: AnalyticsFeatureGate.Feature, workoutsNeeded: Int)?

    /// Error handling
    public var errorMessage: String?

    // MARK: - Dependencies

    private let analyticsService: WorkoutAnalyticsService
    private let qualityScoreService: WorkoutQualityScoreService
    private let featureGate: AnalyticsFeatureGate

    // MARK: - Init

    public init(
        analyticsService: WorkoutAnalyticsService,
        qualityScoreService: WorkoutQualityScoreService,
        featureGate: AnalyticsFeatureGate
    ) {
        self.analyticsService = analyticsService
        self.qualityScoreService = qualityScoreService
        self.featureGate = featureGate
    }

    // MARK: - Dashboard (loads WorkoutInsights aggregate)

    /// Load all analytics for dashboard as a consistent snapshot
    public func loadDashboardInsights() async {
        isInsightsLoading = true
        defer { isInsightsLoading = false }

        do {
            insights = try await analyticsService.generateInsights()
            nextFeatureUnlock = try? await featureGate.nextUnlock()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load insights: \(error.localizedDescription)"
            insights = .empty
        }
    }

    // MARK: - Per-Workout (outside aggregate)

    public func loadSimilarWorkouts(to workout: Workout, limit: Int = 5) async {
        isSimilarWorkoutsLoading = true
        defer { isSimilarWorkoutsLoading = false }

        do {
            similarWorkouts = try await analyticsService.findSimilarWorkouts(
                to: workout, limit: limit, minSimilarity: 0.7
            )
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load similar workouts: \(error.localizedDescription)"
            similarWorkouts = []
        }
    }

    public func loadQualityScore(for workout: Workout) async {
        isQualityScoreLoading = true
        defer { isQualityScoreLoading = false }

        do {
            qualityScore = try await qualityScoreService.computeScore(for: workout)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to compute quality score: \(error.localizedDescription)"
            qualityScore = nil
        }
    }

    // MARK: - Formatting Helpers

    public func formatSimilarity(_ score: Double) -> String {
        String(format: "%.0f%%", score * 100)
    }

    public func formatVolume(_ volume: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: volume)) ?? "0"
    }

    public func formatRatio(_ ratio: Double) -> String {
        String(format: "%.1f:1", ratio)
    }

    public func severityColor(_ severity: ImbalanceSeverity) -> String {
        switch severity {
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }
}
```

---

## 7. Vectorization Strategy

### 7.1 Vector Schema (18 Dimensions)

| Index | Feature | Range | Description |
|-------|---------|-------|-------------|
| 0 | `total_volume_norm` | 0-1 | Total volume / max observed (50k) |
| 1 | `avg_weight_norm` | 0-1 | Average weight / max (300kg) |
| 2 | `avg_reps_norm` | 0-1 | Average reps / max (30) |
| 3 | `set_count_norm` | 0-1 | Total sets / max (100) |
| 4 | `exercise_diversity` | 0-1 | Unique exercises / max (15) |
| 5 | `duration_norm` | 0-1 | Duration / max (2 hours) |
| 6 | `chest_ratio` | 0-1 | % volume on chest |
| 7 | `back_ratio` | 0-1 | % volume on back |
| 8 | `legs_ratio` | 0-1 | % volume on legs (quads+hams+glutes+calves) |
| 9 | `shoulders_ratio` | 0-1 | % volume on shoulders |
| 10 | `arms_ratio` | 0-1 | % volume on arms (biceps+triceps) |
| 11 | `core_ratio` | 0-1 | % volume on core |
| 12 | `compound_ratio` | 0-1 | % barbell exercises |
| 13 | `avg_rpe` | 0-1 | Average RPE / 10 |
| 14 | `volume_vs_prev_7d` | -1 to 1 | % change vs 7-day MA (clamped) |
| 15 | `volume_vs_prev_30d` | -1 to 1 | % change vs 30-day MA (clamped) |
| 16 | `pr_count_norm` | 0-1 | PRs in workout / max (10) |
| 17 | `time_of_day_sin` | 0-1 | sin(hour / 24 * 2π) * 0.5 + 0.5 |

### 7.2 Normalization Approach

**L2 Normalization (for cosine similarity):**
- All vectors L2 normalized: `||v|| = 1`
- Cosine similarity = dot product: `cos(θ) = v1 · v2`
- Range: -1 (opposite) to 1 (identical)
- Typical threshold: 0.7+ for "similar"

**Feature Scaling:**
- Min-max scaling to [0, 1] before L2 normalization
- Max values from 99th percentile of historical data
- Clamping prevents outliers from dominating

### 7.3 Vectorization Timing

**When vectors are created:**

1. **Post-workout completion** (primary):
   - Triggered by `WorkoutRepository.complete(workoutId)`
   - Background task via Swift concurrency
   - No UI blocking

2. **On-demand** (fallback):
   - When analytics view is opened and vector is missing
   - `WorkoutAnalyticsService.ensureVectorized(workout)`

3. **Batch migration** (one-time):
   - `WorkoutAnalyticsService.vectorizeAllWorkouts()`
   - Called during app upgrade or first analytics access
   - Shows progress indicator

**Performance targets:**
- Single vectorization: <50ms
- Batch 100 workouts: <5 seconds
- UI remains responsive (async/await)

---

## 8. Performance Design

### 8.1 Caching Strategy

**In-Memory Cache (WorkoutAnalyticsService):**
```swift
private var cachedVectors: [UUID: WorkoutVector] = [:]
private var cacheTimestamp: Date?
private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
```

**Cache Invalidation:**
- After 5 minutes
- After new workout is saved
- After vector is manually refreshed

**ViewModel Cache:**
- ViewModels cache loaded data
- Invalidate on pull-to-refresh
- Persist in `UserDefaults` for offline access

### 8.2 Lazy Computation

**On-Demand Loading:**
```swift
// Dashboard shows placeholder until user taps "Analytics"
public func loadAnalyticsIfNeeded() async {
    guard plateaus.isEmpty && muscleBalance == nil else { return }
    await loadAllAnalytics()
}
```

**Pagination:**
```swift
// Load similar workouts in batches
public func loadMoreSimilarWorkouts() async {
    let nextBatch = try await analyticsService.findSimilarWorkouts(
        to: currentWorkout,
        limit: 10,
        offset: similarWorkouts.count
    )
    similarWorkouts.append(contentsOf: nextBatch)
}
```

### 8.3 Background Processing

**Swift Concurrency Patterns:**
```swift
// Single aggregate load replaces parallel independent calls.
// generateInsights() internally runs plateau, muscle balance, and
// recommendations in structured concurrency, returning a WorkoutInsights snapshot.
await loadDashboardInsights()
```

**Background Vectorization:**
```swift
Task.detached(priority: .background) {
    await analyticsService.vectorizeAllWorkouts()
}
```

### 8.4 Performance Targets

| Operation | Target | Measured |
|-----------|--------|----------|
| Single vectorization | <50ms | TBD |
| Vector search (2000 workouts) | <5ms | TBD |
| Plateau analysis (100 workouts) | <100ms | TBD |
| Muscle balance analysis | <50ms | TBD |
| Full analytics dashboard load | <500ms | TBD |

### 8.5 Memory Management

**Vector Storage:**
- Float32 (4 bytes) vs Double (8 bytes): 50% savings
- 18 dimensions × 4 bytes = 72 bytes per vector
- 2000 workouts = 144 KB total

**SwiftData Optimizations:**
- `@Attribute(.externalStorage)` for vector data
- Denormalized fields (totalVolume, workoutDate) for faster querying
- Indexed workoutId for O(log n) lookup

---

## 9. Testing Strategy

### 9.1 Unit Tests

**Domain Models:**
- `WorkoutVectorTests` - Validate 18-dimension constraint, Codable
- `SimilarWorkoutTests` - Equality, hashing
- `PlateauAnalysisTests` - Business logic validation

**Services:**
- `WorkoutVectorizerTests` - Feature extraction correctness, normalization
- `VectorSearchServiceTests` - Similarity computation, top-K results
- `PlateauDetectionServiceTests` - Plateau detection accuracy
- `MuscleBalanceServiceTests` - Imbalance detection, recommendations

**Repository:**
- `SwiftDataAnalyticsRepositoryTests` - CRUD operations, SwiftData mocking

**ViewModel:**
- `WorkoutAnalyticsViewModelTests` - State management, loading states, error handling

### 9.2 Mock Boundaries

**Protocol-Based Mocking:**
```swift
// Test doubles
final class MockAnalyticsRepository: AnalyticsRepository {
    var storedVectors: [WorkoutVector] = []

    func storeVector(_ vector: WorkoutVector) async throws {
        storedVectors.append(vector)
    }

    // ... other methods
}
```

**Test Data Builders:**
```swift
extension Workout {
    static func testWorkout(
        volume: Double = 10000,
        exercises: Int = 5,
        date: Date = Date()
    ) -> Workout {
        // Builder pattern for test data
    }
}
```

### 9.3 Test Data Approach

**Fixture Data:**
```swift
struct TestFixtures {
    static let sampleWorkouts: [Workout] = [
        // 10 pre-defined workouts with varied characteristics
    ]

    static let sampleVectors: [WorkoutVector] = [
        // Pre-computed vectors for fast tests
    ]
}
```

**Property-Based Testing:**
```swift
func testVectorizationPreservesNormalization() {
    for _ in 0..<100 {
        let workout = Workout.random()
        let vector = vectorizer.vectorize(workout)
        let magnitude = sqrt(vector.dimensions.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.001)
    }
}
```

### 9.4 Integration Tests

**End-to-End Flows:**
```swift
func testCompleteWorkoutCreatesVector() async throws {
    // Given: User completes workout
    let workout = Workout.testWorkout()
    try await workoutRepository.save(workout)
    try await workoutRepository.complete(workout.id)

    // When: Vector is created in background
    try await analyticsService.vectorizeWorkout(workout)

    // Then: Vector is stored and retrievable
    let vector = try await analyticsRepository.fetchVector(for: workout.id)
    XCTAssertNotNil(vector)
}
```

---

## 10. Migration & Rollout

### 10.1 Schema Migration

**SwiftData Schema Versioning:**
```swift
// AppContainer.swift - Updated schema
let schema = Schema([
    // Existing entities
    ExerciseEntity.self,
    WorkoutEntity.self,
    // ... existing ...

    // NEW entity
    WorkoutVectorEntity.self
])
```

**Migration Plan:**
- SwiftData handles schema migration automatically (lightweight migration)
- New relationship `WorkoutEntity.workoutVector` is optional
- No data loss - existing workouts preserved

### 10.2 Vectorization of Existing Workouts

**One-Time Migration Task:**
```swift
// iOS/App/StrengthTrackeriOS.swift
.task {
    await performAnalyticsMigration()
}

private func performAnalyticsMigration() async {
    let needsMigration = UserDefaults.standard.bool(forKey: "analytics_migration_complete")

    guard !needsMigration else { return }

    do {
        try await container.makeAnalyticsService().vectorizeAllWorkouts()
        UserDefaults.standard.set(true, forKey: "analytics_migration_complete")
    } catch {
        print("Analytics migration failed: \(error)")
    }
}
```

**Progress Indicator:**
```swift
@State private var migrationProgress: Double = 0.0
@State private var showMigrationSheet = false

// Show progress sheet during migration
.sheet(isPresented: $showMigrationSheet) {
    MigrationProgressView(progress: $migrationProgress)
}
```

### 10.3 Progressive Disclosure (Data-Driven Feature Unlocking)

Features unlock automatically based on the user's workout count, aligned with the UX progressive disclosure phases. No manual feature flags needed.

**File: `Shared/Services/Analytics/AnalyticsFeatureGate.swift`**

```swift
import Foundation

/// Controls which analytics features are available based on workout history.
/// Features unlock progressively as the user accumulates data, ensuring
/// meaningful insights and avoiding empty-state confusion.
///
/// Aligned with UX progressive disclosure phases:
/// - Phase 1 (1-5 workouts): Basic stats, PR tracking only
/// - Phase 2 (5-20 workouts): Quality score, basic trends, recommendations
/// - Phase 3 (20-50 workouts): Plateau detection, muscle balance, recovery
/// - Phase 4 (50+ workouts): Volume optimization, cycle comparisons, predictions
@MainActor
public final class AnalyticsFeatureGate: Sendable {

    public enum Feature: CaseIterable, Sendable {
        case qualityScore           // Phase 2: 5+ workouts
        case strengthTrends         // Phase 2: 5+ workouts
        case exerciseRecommendations // Phase 2: 5+ workouts
        case similarWorkouts        // Phase 2: 10+ workouts
        case muscleBalance          // Phase 3: 20+ workouts
        case recoveryTimeline       // Phase 3: 20+ workouts
        case plateauDetection       // Phase 3: 20+ workouts (needs 8+ weeks of data)
        case volumeOptimization     // Phase 4: 50+ workouts
        case cycleComparisons       // Phase 4: 50+ workouts
        case predictiveAnalytics    // Phase 4: 50+ workouts
    }

    private static let thresholds: [Feature: Int] = [
        .qualityScore: 5,
        .strengthTrends: 5,
        .exerciseRecommendations: 5,
        .similarWorkouts: 10,
        .muscleBalance: 20,
        .recoveryTimeline: 20,
        .plateauDetection: 20,
        .volumeOptimization: 50,
        .cycleComparisons: 50,
        .predictiveAnalytics: 50,
    ]

    private let workoutRepository: any WorkoutRepository

    public init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    /// Check if a feature is unlocked for the current user
    public func isUnlocked(_ feature: Feature) async throws -> Bool {
        let count = try await workoutRepository.fetchCompletedCount()
        let threshold = Self.thresholds[feature] ?? 0
        return count >= threshold
    }

    /// Get all currently unlocked features
    public func unlockedFeatures() async throws -> Set<Feature> {
        let count = try await workoutRepository.fetchCompletedCount()
        return Set(Feature.allCases.filter { feature in
            let threshold = Self.thresholds[feature] ?? 0
            return count >= threshold
        })
    }

    /// Workouts needed to unlock the next feature
    public func nextUnlock() async throws -> (feature: Feature, workoutsNeeded: Int)? {
        let count = try await workoutRepository.fetchCompletedCount()
        let locked = Feature.allCases
            .filter { (Self.thresholds[$0] ?? 0) > count }
            .sorted { (Self.thresholds[$0] ?? 0) < (Self.thresholds[$1] ?? 0) }

        guard let next = locked.first,
              let threshold = Self.thresholds[next] else { return nil }

        return (next, threshold - count)
    }
}
```

**Usage in ViewModels:**
```swift
// WorkoutAnalyticsViewModel — loads WorkoutInsights aggregate
public func loadDashboardInsights() async {
    isInsightsLoading = true
    defer { isInsightsLoading = false }

    do {
        // generateInsights() respects feature gate internally —
        // returns empty arrays for locked features
        insights = try await analyticsService.generateInsights()
        nextFeatureUnlock = try? await featureGate.nextUnlock()
        errorMessage = nil
    } catch {
        errorMessage = "Failed to load insights: \(error.localizedDescription)"
        insights = .empty
    }
}
```

**Rollout Phases (App Store):**

**Phase 1: Internal Testing** (v1.1-beta)
- Feature gate enabled, all thresholds active
- Collect crash reports, performance metrics

**Phase 2: Beta Users** (v1.2-beta)
- TestFlight beta with progressive disclosure
- Monitor analytics performance, user engagement

**Phase 3: General Availability** (v1.3)
- Ship to all users
- Features unlock automatically per workout count
- Settings: opt-out toggle for analytics insights

### 10.4 Backward Compatibility

**Graceful Degradation:**
```swift
// If vector doesn't exist, fall back to non-vector analytics
public func findSimilarWorkouts(to workout: Workout) async throws -> [SimilarWorkout] {
    do {
        return try await findSimilarWorkoutsWithVectors(to: workout)
    } catch AnalyticsError.vectorNotFound {
        // Fallback: Use simpler heuristics (muscle group overlap, volume similarity)
        return findSimilarWorkoutsWithoutVectors(to: workout)
    }
}
```

---

## 11. Future Extensions

### 11.1 HNSW Indexing

**When to Add:**
- User has 5,000+ workouts
- Linear scan exceeds 10ms

**Library:** `SimilaritySearchKit` (Swift package)
```swift
import SimilaritySearchKit

let index = HNSWIndex(dimensions: 18, metric: .cosine)

for vector in allVectors {
    index.add(vector.dimensions, id: vector.id)
}

let results = index.search(queryVector, k: 10)
```

**Performance Gain:**
- Linear scan: O(n) = 10ms @ 5000 workouts
- HNSW: O(log n) = <1ms @ 5000 workouts

### 11.2 NLContextualEmbedding (iOS 17+)

**Semantic Exercise Search:**
```swift
#if canImport(NaturalLanguage)
import NaturalLanguage

func semanticExerciseSearch(query: String, exercises: [Exercise]) async throws -> [Exercise] {
    let embedding = NLContextualEmbedding.contextualWordEmbedding(for: .english)!

    let queryVector = try await embedding.vector(for: query)

    let scored = exercises.map { exercise in
        let exerciseVector = try await embedding.vector(for: exercise.name)
        let similarity = cosineSimilarity(queryVector, exerciseVector)
        return (exercise, similarity)
    }

    return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
}
#endif
```

**Use Case:**
- "Find exercises like bench press" → Dumbbell press, incline barbell, etc.
- Cross-lingual support (if needed)

### 11.3 Watch App Integration

**Workout Recommendations on Watch:**
```swift
// WatchApp/Features/Analytics/RecommendedExercisesView.swift
struct RecommendedExercisesView: View {
    let viewModel: WorkoutAnalyticsViewModel  // @Observable, not @StateObject

    var body: some View {
        List(viewModel.insights.recommendations) { recommendation in
            ExerciseRecommendationRow(recommendation: recommendation)
        }
        .task {
            await viewModel.loadDashboardInsights()
        }
    }
}
```

**Watch Complications:**
- Show plateau alerts: "Chest: 3 weeks stalled"
- Muscle balance score in complication

### 11.4 Widgets

**Dashboard Widget (iOS Home Screen):**
```swift
struct AnalyticsDashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnalyticsDashboard", provider: Provider()) { entry in
            AnalyticsDashboardView(entry: entry)
        }
        .configurationDisplayName("Workout Analytics")
        .description("View your training insights at a glance")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AnalyticsDashboardView: View {
    let entry: AnalyticsEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text("Muscle Balance: \(formatScore(entry.balanceScore))")
            Text("Plateaus: \(entry.plateauCount)")
            Text("Top Recommendation: \(entry.topRecommendation)")
        }
    }
}
```

### 11.5 Advanced Analytics

**Strength Trend Forecasting:**
- Linear regression on volume progression
- Predict 1RM in 4 weeks
- Confidence intervals

**Recovery Pattern Analysis:**
- Optimal rest days between muscle groups
- Correlation with performance (volume, RPE)
- Personalized recovery recommendations

**Optimal Volume Finder:**
- Correlate volume with PR frequency
- Identify "sweet spot" volume for each exercise
- Avoid overtraining

### 11.6 Push Notifications for Insight Alerts

Aligned with UX push/pull insight strategy: critical insights (plateaus, recovery warnings) can optionally push to the user via local notifications.

**File: `Shared/Services/Analytics/AnalyticsNotificationService.swift`**

```swift
#if canImport(UserNotifications)
import UserNotifications
import Foundation

/// Schedules local notifications for critical analytics insights.
/// Notifications are opt-in via Settings → Notifications.
///
/// Push (proactive) insights:
/// - Plateau alerts (4+ weeks stalled)
/// - Recovery warnings (<24h rest on high-volume muscle group)
/// - Volume warnings (>20% above optimal range)
///
/// Pull (user-initiated, never notified):
/// - Similar workouts, exercise recommendations, strength trends
@MainActor
public final class AnalyticsNotificationService: Sendable {

    public enum NotificationCategory: String, Sendable {
        case plateauAlert = "analytics_plateau"
        case recoveryWarning = "analytics_recovery"
        case volumeWarning = "analytics_volume"
    }

    private let userPreferences: UserPreferencesService

    public init(userPreferences: UserPreferencesService) {
        self.userPreferences = userPreferences
    }

    /// Request notification permission (called once from Settings)
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Schedule a plateau alert notification
    public func notifyPlateau(_ analysis: PlateauAnalysis) async {
        guard userPreferences.plateauNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Plateau Alert"
        content.body = "\(analysis.exerciseName ?? "An exercise") hasn't progressed in \(analysis.consecutiveWeeksStalled) weeks. Tap for recommendations."
        content.categoryIdentifier = NotificationCategory.plateauAlert.rawValue
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "plateau-\(analysis.exerciseId?.uuidString ?? UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedule a recovery warning notification
    public func notifyRecoveryWarning(muscleGroup: MuscleGroup, hoursSinceLastTraining: Int) async {
        guard userPreferences.recoveryNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recovery Reminder"
        content.body = "Your \(muscleGroup.rawValue) might need more rest (\(hoursSinceLastTraining)h since last session). Consider a different muscle group today."
        content.categoryIdentifier = NotificationCategory.recoveryWarning.rawValue
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "recovery-\(muscleGroup.rawValue)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
```

**User Preferences extension (add to `UserPreferencesService`):**
```swift
public var plateauNotificationsEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "pref_notify_plateaus") }
    set { UserDefaults.standard.set(newValue, forKey: "pref_notify_plateaus") }
}

public var recoveryNotificationsEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "pref_notify_recovery") }
    set { UserDefaults.standard.set(newValue, forKey: "pref_notify_recovery") }
}
```

**Settings UI (aligned with UX Settings Copy):**
- Plateau Alerts: Toggle (default: on)
- Recovery Reminders: Toggle (default: on)
- Weekly Summaries: Toggle (default: off, Phase 4)

---

## Appendix A: File Paths Reference

### Domain Models
- `Shared/Models/Domain/Analytics/WorkoutVector.swift`
- `Shared/Models/Domain/Analytics/SimilarWorkout.swift`
- `Shared/Models/Domain/Analytics/PlateauAnalysis.swift`
- `Shared/Models/Domain/Analytics/MuscleBalance.swift`
- `Shared/Models/Domain/Analytics/ExerciseRecommendation.swift`
- `Shared/Models/Domain/Analytics/RecoveryPattern.swift`
- `Shared/Models/Domain/Analytics/OptimalVolumeRange.swift`
- `Shared/Models/Domain/Analytics/WorkoutQualityScore.swift`
- `Shared/Models/Domain/Analytics/WorkoutInsights.swift`

### Mappers
- `Shared/Persistence/Mappers/WorkoutVectorMapper.swift`

### Services
- `Shared/Services/Analytics/WorkoutVectorizer.swift`
- `Shared/Services/Analytics/VectorSearchService.swift`
- `Shared/Services/Analytics/WorkoutAnalyticsService.swift`
- `Shared/Services/Analytics/PlateauDetectionService.swift`
- `Shared/Services/Analytics/MuscleBalanceService.swift`
- `Shared/Services/Analytics/ExerciseRecommendationService.swift`
- `Shared/Services/Analytics/WorkoutQualityScoreService.swift`
- `Shared/Services/Analytics/AnalyticsFeatureGate.swift`
- `Shared/Services/Analytics/AnalyticsNotificationService.swift`

### Repositories
- `Shared/Repositories/Protocols/AnalyticsRepository.swift`
- `Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift`

### Entities
- `Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift`

### ViewModels
- `Shared/ViewModels/WorkoutAnalyticsViewModel.swift`

### Views (iOS)
- `iOS/Features/Analytics/WorkoutAnalyticsView.swift` (future)
- `iOS/Features/Analytics/SimilarWorkoutsView.swift` (future)
- `iOS/Features/Analytics/PlateauAnalysisView.swift` (future)
- `iOS/Features/Analytics/MuscleBalanceView.swift` (future)

### Tests
- `Tests/StrengthTrackerTests/Analytics/WorkoutVectorizerTests.swift`
- `Tests/StrengthTrackerTests/Analytics/VectorSearchServiceTests.swift`
- `Tests/StrengthTrackerTests/Analytics/WorkoutAnalyticsServiceTests.swift`
- `Tests/StrengthTrackerTests/Analytics/WorkoutAnalyticsViewModelTests.swift`

---

## Appendix B: AppContainer Integration

**Updated `AppContainer.swift` (lines to add):**

```swift
// Line 32: Add analytics services
public let analyticsService: WorkoutAnalyticsService
public let vectorizer: WorkoutVectorizer
public let searchService: VectorSearchService
public let plateauService: PlateauDetectionService
public let muscleBalanceService: MuscleBalanceService
public let recommendationService: ExerciseRecommendationService
public let qualityScoreService: WorkoutQualityScoreService
public let analyticsFeatureGate: AnalyticsFeatureGate
public let analyticsNotificationService: AnalyticsNotificationService

// Line 47: Add analytics repository
public let analyticsRepository: any AnalyticsRepository

// Line 50: Wire up analytics repository (vector-only, no workoutRepository dependency)
analyticsRepository = SwiftDataAnalyticsRepository(modelContext: modelContext)

// Line 53: Wire up analytics services
vectorizer = WorkoutVectorizer()
searchService = VectorSearchService()
plateauService = PlateauDetectionService()
muscleBalanceService = MuscleBalanceService()
recommendationService = ExerciseRecommendationService()
qualityScoreService = WorkoutQualityScoreService(
    workoutRepository: workoutRepository,
    muscleBalanceService: muscleBalanceService
)
analyticsFeatureGate = AnalyticsFeatureGate(workoutRepository: workoutRepository)
analyticsNotificationService = AnalyticsNotificationService(
    plateauService: plateauService,
    workoutRepository: workoutRepository
)
analyticsService = WorkoutAnalyticsService(
    analyticsRepository: analyticsRepository,
    workoutRepository: workoutRepository,
    exerciseRepository: exerciseRepository,
    vectorizer: vectorizer,
    searchService: searchService,
    plateauService: plateauService,
    muscleBalanceService: muscleBalanceService,
    recommendationService: recommendationService
)

// Add factory method (after line 126)
public func makeWorkoutAnalyticsViewModel() -> WorkoutAnalyticsViewModel {
    WorkoutAnalyticsViewModel(
        analyticsService: analyticsService,
        qualityScoreService: qualityScoreService,
        featureGate: analyticsFeatureGate
    )
}
```

---

## Architecture Decision Records (ADRs)

### ADR-001: Pure On-Device Vector Analytics
**Context:** Need workout similarity search and analytics without cloud costs.
**Decision:** Use feature-engineered vectors (18 dims) + Accelerate vDSP for cosine similarity.
**Rationale:** Workout data is already numeric, no LLM needed. Linear scan <5ms for 2000 workouts.
**Alternatives:** OpenAI embeddings (costly, network latency), Core ML (overkill).

### ADR-002: Double for Computation, Float32 for Storage
**Context:** Need balance between computational precision and storage efficiency.
**Decision:** Use `Double` (64-bit) in domain models (`WorkoutVector.dimensions: [Double]`) and service-layer computation (`VectorSearchService`, `WorkoutVectorizer`). Use `Float32` (32-bit) only for SwiftData persistence via `WorkoutVectorEntity.vectorData`.
**Rationale:** Double precision avoids cumulative floating-point errors in L2 normalization and cosine similarity. Float32 storage saves 50% space (72 bytes vs 144 bytes per vector). Conversion happens only at the repository boundary (`vectorToData`/`dataToVector`).
**Trade-offs:** Precision loss <0.0001 in similarity scores after round-trip (acceptable). Slight overhead from Float↔Double conversion at storage boundary (negligible).

### ADR-003: L2 Normalization for Cosine Similarity
**Context:** Need fast, interpretable similarity metric.
**Decision:** L2 normalize all vectors, use dot product for cosine similarity.
**Rationale:** `cos(θ) = v1 · v2` when `||v1|| = ||v2|| = 1`. Single BLAS call, <1ms.
**Alternatives:** Euclidean distance (less interpretable), Manhattan distance (poor for high-dim).

### ADR-004: SwiftData for Vector Storage
**Context:** Need persistent storage for vectors.
**Decision:** Store as `WorkoutVectorEntity` in SwiftData, linked to `WorkoutEntity`.
**Rationale:** Leverages existing persistence layer, cascade delete, ACID guarantees.
**Trade-offs:** Slightly slower than pure in-memory, but acceptable (<5ms fetch).

### ADR-005: Background Vectorization
**Context:** Vectorization must not block UI.
**Decision:** Vectorize in background task after workout completion.
**Rationale:** 50ms vectorization time is noticeable if synchronous.
**Implementation:** `Task.detached(priority: .background)`

### ADR-006: Data-Driven Progressive Disclosure
**Context:** Analytics features need minimum data to produce meaningful insights. Showing empty screens to new users hurts engagement.
**Decision:** Use `AnalyticsFeatureGate` with workout-count thresholds (5/10/20/50) to automatically unlock features. No manual feature flags.
**Rationale:** Aligned with UX progressive disclosure phases. Encourages consistency ("3 more workouts to unlock Muscle Balance"). Prevents overwhelming beginners while giving advanced users full access.
**Alternatives:** Boolean feature flags (too manual, not user-driven), server-side flags (overkill for on-device app).

### ADR-007: Local Notifications for Critical Insights
**Context:** Plateau and recovery alerts are time-sensitive and actionable even when the user isn't in the app.
**Decision:** Use `UNUserNotificationCenter` for local push notifications on critical insights (plateau alerts, recovery warnings). Opt-in via Settings.
**Rationale:** Local notifications require no backend, work offline, and respect privacy. Only critical/actionable insights push; exploratory insights remain pull-only.
**Trade-offs:** Notification fatigue if thresholds are too aggressive. Mitigated by conservative defaults (plateau: 4+ weeks, recovery: <24h + high volume only).

---

**End of Architecture Document**

This architecture provides a scalable, performant, and testable foundation for vector-based workout analytics in StrengthTracker. All components follow the existing DDD patterns and Swift 6 concurrency model.
