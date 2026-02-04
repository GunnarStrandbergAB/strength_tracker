#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class BodyMeasurementEntity {
    @Attribute(.unique) var id: UUID
    var date: Date
    var measurementType: String
    var value: Double
    var unit: String
    var notes: String?

    init(
        id: UUID,
        date: Date,
        measurementType: String,
        value: Double,
        unit: String,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.measurementType = measurementType
        self.value = value
        self.unit = unit
        self.notes = notes
    }
}
#endif
