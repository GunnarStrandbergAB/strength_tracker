import Foundation

public struct BodyMeasurement: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var date: Date
    public var measurementType: MeasurementType
    public var value: Double
    public var unit: String
    public var notes: String?

    public init(id: UUID, date: Date, measurementType: MeasurementType, value: Double, unit: String, notes: String?) {
        self.id = id
        self.date = date
        self.measurementType = measurementType
        self.value = value
        self.unit = unit
        self.notes = notes
    }
}
