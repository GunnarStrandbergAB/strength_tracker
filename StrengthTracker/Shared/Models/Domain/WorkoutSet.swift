import Foundation

// MARK: - Intensity Recording

/// Shared intensity + failure semantics for anything that records a performed effort:
/// a whole set, or one drop-set segment. RPE and RIR are two views of the same scale
/// (see `IntensityMetric`); entering either stores both so RPE-based analytics keep
/// working whichever metric the user logs.
public protocol IntensityRecording {
    var rpe: Double? { get set }
    var rir: Double? { get set }
    var isFailure: Bool { get set }
}

extension IntensityRecording {
    /// Stores RPE and derives+stores the matching RIR. nil clears both.
    public mutating func applyRPE(_ value: Double?) {
        guard let value else {
            rpe = nil
            rir = nil
            return
        }
        rpe = value
        rir = IntensityMetric.rir(fromRPE: value)
    }

    /// Stores RIR and derives+stores the matching RPE. nil clears both.
    public mutating func applyRIR(_ value: Double?) {
        guard let value else {
            rpe = nil
            rir = nil
            return
        }
        rir = value
        rpe = IntensityMetric.rpe(fromRIR: value)
    }

    public mutating func applyIntensity(_ value: Double?, metric: IntensityMetric) {
        switch metric {
        case .rpe: applyRPE(value)
        case .rir: applyRIR(value)
        }
    }

    /// The stored value for the given metric, deriving from the counterpart when only
    /// the other metric was recorded (e.g. legacy RPE-only history viewed as RIR).
    public func intensityValue(for metric: IntensityMetric) -> Double? {
        switch metric {
        case .rpe:
            if let rpe { return rpe }
            return rir.map(IntensityMetric.rpe(fromRIR:))
        case .rir:
            if let rir { return rir }
            return rpe.map(IntensityMetric.rir(fromRPE:))
        }
    }

    /// One-way failure rule: turning failure ON with no intensity recorded defaults to
    /// RIR 0 / RPE 10 (the user can still override). Turning OFF never clears intensity,
    /// and entering RIR 0 through an intensity field never flips this flag.
    public mutating func setFailureFlag(_ isOn: Bool) {
        isFailure = isOn
        if isOn, rpe == nil, rir == nil {
            rir = 0
            rpe = 10
        }
    }
}

// MARK: - Drop Set Segment

/// One performed segment of a drop set: weight, reps, and intensity for a single
/// portion of the descending sequence. A grouped drop set stores ALL its segments as
/// `DropSetEntry` values, including the first/top one.
public struct DropSetEntry: Identifiable, Hashable, Sendable, Codable, IntensityRecording {
    public let id: UUID
    public var weight: Double?
    public var reps: Int?
    public var rpe: Double?
    public var rir: Double?
    public var isFailure: Bool

    public init(
        id: UUID = UUID(),
        weight: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        isFailure: Bool = false
    ) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.isFailure = isFailure
    }
}

// MARK: - Side efforts

public enum BodySide: String, Codable, CaseIterable, Sendable {
    case left, right
    public var title: String { rawValue.capitalized }
}

/// A named side inside ONE logical set. A side may itself contain drop segments.
/// Keeping this separate from DropSetEntry prevents treating L/R as descending loads.
public struct SideSetEntry: Identifiable, Hashable, Sendable, Codable {
    public var side: BodySide
    public var effort: ExerciseSet
    public var id: BodySide { side }
    public init(side: BodySide, effort: ExerciseSet) {
        self.side = side
        var copy = effort
        copy.sideSets = nil
        self.effort = copy
    }
}

// MARK: - Exercise Set

public struct ExerciseSet: Identifiable, Hashable, Sendable, Codable, IntensityRecording {
    public let id: UUID
    public var order: Int
    public var setType: SetType
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var rir: Double?
    public var isCompleted: Bool
    public var isPersonalRecord: Bool
    public var isFailure: Bool
    public var completedAt: Date?
    /// nil is the ordinary compact row. Values contain each side's actual load,
    /// reps, effort and completion; the parent is a compatibility summary only.
    public fileprivate(set) var sideSets: [SideSetEntry]?
    public var isFullyCompleted: Bool { sideSets.map { !$0.isEmpty && $0.allSatisfy { $0.effort.isCompleted } } ?? isCompleted }
    public var completedSideCount: Int { sideSets?.filter { $0.effort.isCompleted }.count ?? 0 }
    public var hasStartedSides: Bool { sideSets?.contains { $0.effort.isCompleted } == true }
    public var workingSetCredit: Double {
        guard setType != .warmup else { return 0 }
        if sideSets != nil { return Double(sideSets?.filter { $0.effort.isCompleted && $0.effort.setType != .warmup }.count ?? 0) / 2 }
        return isCompleted ? 1 : 0
    }
    /// Drop-set segments, INCLUDING the first/top one. Invariant (maintained by
    /// `applyDropSets(_:)`, the only mutation path): when non-empty, `setType` is
    /// `.dropset` and the parent `weight/reps/rpe/rir/isFailure` mirror `dropSets[0]`
    /// so legacy readers keep seeing the set's top segment. Never sum parent fields
    /// AND these entries — that double-counts the top segment; volume must go through
    /// `setVolume`. Legacy single-row `.dropset` history has this empty.
    public private(set) var dropSets: [DropSetEntry]

    /// True for grouped drop sets and for legacy single-row `.dropset` history.
    public var isDropSet: Bool { !dropSets.isEmpty || setType == .dropset }

    /// The performed segments: the drop entries when grouped, otherwise one part built
    /// from the set's own fields (`id` == set id). Calculation sites that care about
    /// individual efforts (PRs, e1RM candidates, rep totals) iterate this.
    public var effectiveParts: [DropSetEntry] {
        if let sideSets { return sideSets.filter { $0.effort.isCompleted }.flatMap { $0.effort.effectiveParts } }
        return dropSets.isEmpty
            ? [DropSetEntry(id: id, weight: weight, reps: reps, rpe: rpe, rir: rir, isFailure: isFailure)]
            : dropSets
    }

    /// Total reps across all segments (a plain set has one segment).
    public var totalReps: Int {
        effectiveParts.reduce(0) { $0 + ($1.reps ?? 0) }
    }

    /// Drop-aware volume under the effective-load model: sums load×reps across
    /// `effectiveParts` (sub-entries ONLY for grouped drop sets — the parent mirrors
    /// the top segment and must not be added). `baseLoadPerRep` is the bodyweight
    /// base (`Exercise.baseLoadPerRep(bodyWeightKg:)`) or nil for external-load
    /// exercises. Returns 0 unless the set is completed and non-warmup.
    /// There is deliberately NO body-weight-blind variant — volume cannot be computed
    /// without knowing the base load.
    public func setVolume(baseLoadPerRep: Double?, multiplier: Double = 1, recording: WeightRecording? = nil) -> Double {
        guard isCompleted, setType != .warmup else { return 0 }
        if let sideSets {
            var total = 0.0
            let loadMultiplier = recording?.sideExternalMultiplier ?? 1
            for side in sideSets where side.effort.isCompleted && side.effort.setType != .warmup {
                for part in side.effort.effectiveParts {
                    let load = (baseLoadPerRep ?? 0) * (recording?.sideBaseMultiplier ?? 1) + (part.weight ?? 0) * loadMultiplier
                    total += load * Double(part.reps ?? 0)
                }
            }
            return total
        }
        return effectiveParts.reduce(0) { sum, part in
            guard let recording else { return sum + (part.effectiveLoad(baseLoadPerRep: baseLoadPerRep) ?? 0) * Double(part.reps ?? 0) * multiplier }
            let load = (baseLoadPerRep ?? 0) + (part.weight ?? 0) * recording.externalLoadMultiplier
            return sum + load * Double(part.reps ?? 0) * recording.repetitionMultiplier
        }
    }

    public mutating func applySideSets(_ entries: [SideSetEntry]?) {
        guard let entries, !entries.isEmpty else { sideSets = nil; return }
        // No duplicate sides or recursively nested sets can enter calculations.
        var seen = Set<BodySide>()
        sideSets = entries.filter { seen.insert($0.side).inserted }.map { SideSetEntry(side: $0.side, effort: $0.effort) }
        dropSets = []
        setType = sideSets!.allSatisfy { $0.effort.setType == .warmup } ? .warmup : .normal
        let completed = sideSets!.filter { $0.effort.isCompleted }
        isCompleted = !completed.isEmpty
        completedAt = completed.compactMap { $0.effort.completedAt }.max()
        // A conservative summary for legacy consumers; side-aware readers use the entries.
        let summary = completed.min { ($0.effort.weight ?? 0) < ($1.effort.weight ?? 0) } ?? sideSets!.first!
        weight = summary.effort.weight
        reps = summary.effort.reps
        let efforts = completed.compactMap { $0.effort.rpe }
        rpe = efforts.isEmpty ? nil : efforts.reduce(0, +) / Double(efforts.count)
        rir = rpe.map(IntensityMetric.rir(fromRPE:))
        isFailure = completed.contains { $0.effort.isFailure }
    }

    public func canSeparateSides(recording: WeightRecording) -> Bool {
        sideSets == nil && recording.supportsSeparateSides && effectiveParts.allSatisfy { $0.reps == nil || recording.strengthReps($0.reps!) != nil }
    }
    public mutating func separateSides(recording: WeightRecording, onlySide: BodySide? = nil) {
        guard canSeparateSides(recording: recording), recording.repetitions != .oneSide || onlySide != nil else { return }
        var effort = self
        let scale = recording.sideWeightScale
        effort.weight = weight.map { $0 * scale }
        effort.reps = reps.flatMap { recording.strengthReps($0) }
        if !dropSets.isEmpty {
            effort.applyDropSets(dropSets.map { part in
                var copy = part
                copy.weight = part.weight.map { $0 * scale }
                copy.reps = part.reps.flatMap { recording.strengthReps($0) }
                return copy
            })
        }
        applySideSets((onlySide.map { [$0] } ?? BodySide.allCases).map { side in
            let copy = ExerciseSet(id: UUID(), order: effort.order, setType: effort.setType,
                weight: effort.weight, reps: effort.reps, durationSeconds: effort.durationSeconds, distanceMeters: effort.distanceMeters,
                rpe: effort.rpe, rir: effort.rir, isCompleted: effort.isCompleted, isPersonalRecord: false,
                isFailure: effort.isFailure, completedAt: effort.completedAt,
                dropSets: effort.dropSets.map { DropSetEntry(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, rir: $0.rir, isFailure: $0.isFailure) })
            return SideSetEntry(side: side, effort: copy)
        })
    }

    public mutating func setCompleted(_ completed: Bool, at date: Date = Date()) {
        if let sides = sideSets {
            applySideSets(sides.map { side in
                var copy = side
                copy.effort.isCompleted = completed
                copy.effort.completedAt = completed ? (copy.effort.completedAt ?? date) : nil
                return copy
            })
        } else {
            isCompleted = completed
            completedAt = completed ? date : nil
        }
    }

    /// The single mutation path for drop-set segments, maintaining the invariants:
    /// non-empty entries ⇒ `setType = .dropset` (adding drops to a warm-up makes it a
    /// working set) and parent fields mirror `entries[0]`; empty ⇒ segments cleared
    /// and a `.dropset` type reverts to `.normal` (parent fields keep their last
    /// mirrored values).
    public mutating func applyDropSets(_ entries: [DropSetEntry]) {
        guard sideSets == nil else { return }
        dropSets = entries
        if let top = entries.first {
            setType = .dropset
            weight = top.weight
            reps = top.reps
            rpe = top.rpe
            rir = top.rir
            isFailure = top.isFailure
        } else if setType == .dropset {
            setType = .normal
        }
    }

    public init(
        id: UUID,
        order: Int,
        setType: SetType,
        weight: Double?,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?,
        rpe: Double?,
        rir: Double? = nil,
        isCompleted: Bool,
        isPersonalRecord: Bool,
        isFailure: Bool = false,
        completedAt: Date?,
        dropSets: [DropSetEntry] = [],
        sideSets: [SideSetEntry]? = nil
    ) {
        self.id = id
        self.order = order
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
        self.rir = rir
        self.isCompleted = isCompleted
        self.isPersonalRecord = isPersonalRecord
        self.isFailure = isFailure
        self.completedAt = completedAt
        self.dropSets = dropSets
        self.sideSets = nil
        if let sideSets { applySideSets(sideSets) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, setType, weight, reps, durationSeconds, distanceMeters
        case rpe, rir, isCompleted, isPersonalRecord, isFailure, completedAt, dropSets, sideSets
    }

    // Custom decoding for backward compatibility — JSON logged before drop sets / RIR /
    // failure flags existed (including payloads from a not-yet-updated Watch) decodes
    // with safe defaults; a legacy `.failure` set type carries the flag over.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        setType = try container.decode(SetType.self, forKey: .setType)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        rir = try container.decodeIfPresent(Double.self, forKey: .rir)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isPersonalRecord = try container.decode(Bool.self, forKey: .isPersonalRecord)
        isFailure = try container.decodeIfPresent(Bool.self, forKey: .isFailure) ?? (setType == .failure)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        dropSets = try container.decodeIfPresent([DropSetEntry].self, forKey: .dropSets) ?? []
        sideSets = nil
        if let sides = try container.decodeIfPresent([SideSetEntry].self, forKey: .sideSets) { applySideSets(sides) }
    }
}

// MARK: - Workout Exercise

public struct WorkoutExercise: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var exercise: Exercise
    public var order: Int
    public var supersetGroup: Int?
    public var notes: String?
    public var restTimerSeconds: Int?
    public var sets: [ExerciseSet]

    public var workingSetCredits: Double {
        sets.reduce(0) { total, set in
            total + set.workingSetCredit * (set.sideSets == nil && exercise.strengthRecording?.repetitions == .oneSide ? 0.5 : 1)
        }
    }

    /// Effective-load volume: bodyweight-rep exercises count bw × factor + extra kg
    /// per rep (drop-set segments individually); external-load exercises are unchanged.
    public func exerciseVolume(bodyWeightKg: Double) -> Double {
        sets.reduce(0) { $0 + exercise.volume(of: $1, bodyWeightKg: bodyWeightKg) }
    }

    public init(id: UUID, exercise: Exercise, order: Int, supersetGroup: Int?, notes: String?, restTimerSeconds: Int?, sets: [ExerciseSet]) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.sets = sets
    }
}
