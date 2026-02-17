import Foundation

/// Errors thrown by analytics services
public enum AnalyticsError: Error, Sendable {
    case vectorNotFound
    case insufficientData
    case invalidTimeWindow
}
