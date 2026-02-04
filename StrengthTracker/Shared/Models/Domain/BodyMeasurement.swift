import Foundation

struct BodyMeasurement: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var date: Date
    var measurementType: MeasurementType
    var value: Double
    var unit: String
    var notes: String?
}
