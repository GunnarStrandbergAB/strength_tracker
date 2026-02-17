import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WorkoutVectorMapper")
struct WorkoutVectorMapperTests {

    // MARK: - Helpers

    /// Standard 18-dimension vector with known values for testing
    private static let standardDimensions: [Double] = [
        0.65,  // total_volume_norm
        0.45,  // avg_weight_norm
        0.33,  // avg_reps_norm
        0.20,  // set_count_norm
        0.40,  // exercise_diversity
        0.50,  // duration_norm
        0.30,  // chest_ratio
        0.25,  // back_ratio
        0.15,  // legs_ratio
        0.10,  // shoulders_ratio
        0.12,  // arms_ratio
        0.08,  // core_ratio
        0.60,  // compound_ratio
        0.70,  // avg_rpe
        0.05,  // volume_vs_prev_7d
        -0.10, // volume_vs_prev_30d
        0.20,  // pr_count_norm
        0.75,  // time_of_day_sin
    ]

    // MARK: - doublesToData / dataToDoubles round-trip

    @Test("doublesToData produces correct byte count for 18 dimensions")
    func doublesToDataByteCount() {
        let data = WorkoutVectorMapper.doublesToData(Self.standardDimensions)
        // 18 floats * 4 bytes each = 72 bytes
        #expect(data.count == 72)
    }

    @Test("Round-trip doublesToData/dataToDoubles preserves values within Float32 precision")
    func roundTripPreservesValues() {
        let original = Self.standardDimensions
        let data = WorkoutVectorMapper.doublesToData(original)
        let restored = WorkoutVectorMapper.dataToDoubles(data)

        #expect(restored.count == original.count)

        // Float32 has ~7 decimal digits of precision
        for (orig, rest) in zip(original, restored) {
            #expect(abs(orig - rest) < 1e-6, "Expected \(orig) ~= \(rest)")
        }
    }

    @Test("Round-trip preserves negative values within Float32 precision")
    func roundTripNegativeValues() {
        let dims: [Double] = Array(repeating: 0.0, count: 16) + [-0.5, -0.99]
        // Pad to 18 dimensions
        let data = WorkoutVectorMapper.doublesToData(dims)
        let restored = WorkoutVectorMapper.dataToDoubles(data)

        #expect(restored.count == 18)
        #expect(abs(restored[16] - (-0.5)) < 1e-6)
        #expect(abs(restored[17] - (-0.99)) < 1e-6)
    }

    @Test("Round-trip preserves zero values")
    func roundTripZeroValues() {
        let dims = [Double](repeating: 0.0, count: 18)
        let data = WorkoutVectorMapper.doublesToData(dims)
        let restored = WorkoutVectorMapper.dataToDoubles(data)

        #expect(restored.count == 18)
        for value in restored {
            #expect(value == 0.0)
        }
    }

    @Test("Empty dimensions produces empty Data")
    func emptyDimensions() {
        let data = WorkoutVectorMapper.doublesToData([])
        #expect(data.count == 0)

        let restored = WorkoutVectorMapper.dataToDoubles(data)
        #expect(restored.isEmpty)
    }

    @Test("dataToDoubles handles data not aligned to Float boundary")
    func dataNotAlignedToFloat() {
        // 5 bytes: can only extract 1 Float (4 bytes), remaining 1 byte ignored
        let data = Data([0x00, 0x00, 0x80, 0x3F, 0xFF])
        let restored = WorkoutVectorMapper.dataToDoubles(data)
        #expect(restored.count == 1)
        #expect(abs(restored[0] - 1.0) < 1e-6)
    }

    @Test("Round-trip preserves values near Float32 limits")
    func roundTripEdgeValues() {
        var dims = [Double](repeating: 0.0, count: 18)
        dims[0] = 1.0       // max normalized
        dims[1] = 1e-7      // very small positive
        dims[2] = 0.999999  // near 1.0
        let data = WorkoutVectorMapper.doublesToData(dims)
        let restored = WorkoutVectorMapper.dataToDoubles(data)

        #expect(abs(restored[0] - 1.0) < 1e-6)
        #expect(abs(restored[1] - 1e-7) < 1e-6)
        #expect(abs(restored[2] - 0.999999) < 1e-5) // Float32 precision limit
    }

    // MARK: - WorkoutVector domain model

    @Test("WorkoutVector requires exactly 18 dimensions")
    func vectorDimensionCount() {
        let vector = WorkoutVector(
            id: UUID(),
            workoutId: UUID(),
            dimensions: Self.standardDimensions,
            createdAt: Date()
        )
        #expect(vector.dimensions.count == 18)
    }

    @Test("WorkoutVector featureNames has 18 entries")
    func featureNamesCount() {
        #expect(WorkoutVector.featureNames.count == 18)
    }

    @Test("WorkoutVector conforms to Identifiable, Hashable, Sendable, Codable")
    func vectorConformances() {
        let vector = WorkoutVector(
            id: UUID(),
            workoutId: UUID(),
            dimensions: Self.standardDimensions,
            createdAt: Date()
        )

        // Identifiable
        _ = vector.id

        // Hashable
        var hasher = Hasher()
        vector.hash(into: &hasher)

        // Codable round-trip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try! encoder.encode(vector)
        let decoded = try! decoder.decode(WorkoutVector.self, from: encoded)
        #expect(decoded.id == vector.id)
        #expect(decoded.workoutId == vector.workoutId)
        #expect(decoded.dimensions == vector.dimensions)
    }
}
