#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class BodyMeasurementEntity {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var measurementType: String
    public var value: Double
    public var unit: String
    public var notes: String?

    public init(
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
