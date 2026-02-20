import Foundation

// MARK: - Double Rounding Extension for Progression Module

extension Double {
    /// Rounds to the nearest increment (e.g., 2.5 for barbell plates)
    public func rounded(toNearest increment: Double) -> Double {
        guard increment > 0 else { return self }
        return (self / increment).rounded() * increment
    }
}
