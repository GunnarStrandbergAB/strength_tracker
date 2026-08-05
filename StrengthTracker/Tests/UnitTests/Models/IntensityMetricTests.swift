import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("IntensityMetric Conversion Tests")
struct IntensityMetricTests {

    @Test("spec conversion table maps both directions", arguments: [
        (rir: 4.0, rpe: 6.0),
        (rir: 3.0, rpe: 7.0),
        (rir: 2.0, rpe: 8.0),
        (rir: 1.0, rpe: 9.0),
        (rir: 0.0, rpe: 10.0),
    ])
    func testConversionTable(pair: (rir: Double, rpe: Double)) {
        #expect(IntensityMetric.rpe(fromRIR: pair.rir) == pair.rpe)
        #expect(IntensityMetric.rir(fromRPE: pair.rpe) == pair.rir)
    }

    @Test("fractional values convert linearly")
    func testFractionalConversion() {
        #expect(IntensityMetric.rir(fromRPE: 7.5) == 2.5)
        #expect(IntensityMetric.rpe(fromRIR: 2.5) == 7.5)
    }

    @Test("out-of-range values clamp instead of going negative")
    func testClamping() {
        #expect(IntensityMetric.rir(fromRPE: 12) == 0)
        #expect(IntensityMetric.rpe(fromRIR: 12) == 0)
    }
}

@Suite("IntensityRecording Tests")
struct IntensityRecordingTests {

    private func makeSet() -> ExerciseSet {
        ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 80, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
    }

    @Test("applyRPE stores RPE and derives RIR — on sets and drop segments")
    func testApplyRPEStoresBoth() {
        var set = makeSet()
        set.applyRPE(8)
        #expect(set.rpe == 8)
        #expect(set.rir == 2)

        var entry = DropSetEntry()
        entry.applyRPE(9)
        #expect(entry.rpe == 9)
        #expect(entry.rir == 1)
    }

    @Test("applyRIR stores RIR and derives RPE")
    func testApplyRIRStoresBoth() {
        var set = makeSet()
        set.applyRIR(1)
        #expect(set.rir == 1)
        #expect(set.rpe == 9)
    }

    @Test("applying nil clears both values")
    func testNilClearsBoth() {
        var set = makeSet()
        set.applyRPE(8)
        set.applyRPE(nil)
        #expect(set.rpe == nil)
        #expect(set.rir == nil)

        set.applyRIR(2)
        set.applyRIR(nil)
        #expect(set.rpe == nil)
        #expect(set.rir == nil)
    }

    @Test("applyIntensity dispatches by metric")
    func testApplyIntensityDispatch() {
        var set = makeSet()
        set.applyIntensity(7, metric: .rpe)
        #expect(set.rpe == 7)
        #expect(set.rir == 3)

        set.applyIntensity(0, metric: .rir)
        #expect(set.rir == 0)
        #expect(set.rpe == 10)
    }

    @Test("intensityValue derives from the counterpart for legacy single-metric data")
    func testIntensityValueDerivation() {
        var set = makeSet()
        set.rpe = 8  // legacy RPE-only history

        #expect(set.intensityValue(for: .rpe) == 8)
        #expect(set.intensityValue(for: .rir) == 2)

        var rirOnly = makeSet()
        rirOnly.rir = 1
        #expect(rirOnly.intensityValue(for: .rpe) == 9)

        #expect(makeSet().intensityValue(for: .rir) == nil)
    }

    @Test("failure ON with no intensity recorded defaults RIR 0 / RPE 10")
    func testFailureDefaultsWhenUnset() {
        var set = makeSet()
        set.setFailureFlag(true)
        #expect(set.isFailure == true)
        #expect(set.rir == 0)
        #expect(set.rpe == 10)
    }

    @Test("failure ON preserves an already-recorded intensity")
    func testFailurePreservesExistingIntensity() {
        var set = makeSet()
        set.applyRPE(8)
        set.setFailureFlag(true)
        #expect(set.rpe == 8)
        #expect(set.rir == 2)
    }

    @Test("failure OFF never clears intensity")
    func testFailureOffKeepsIntensity() {
        var set = makeSet()
        set.setFailureFlag(true)
        set.setFailureFlag(false)
        #expect(set.isFailure == false)
        #expect(set.rir == 0)
        #expect(set.rpe == 10)
    }

    @Test("entering RIR 0 does NOT auto-flag failure (one-way rule)")
    func testRIRZeroDoesNotFlagFailure() {
        var set = makeSet()
        set.applyRIR(0)
        #expect(set.rpe == 10)
        #expect(set.isFailure == false)
    }
}
