import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public final class WidgetDataService: Sendable {
    public init() {}

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Write widget data to shared App Group UserDefaults
    public func updateWidgetData(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId) else { return }
        if let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: WidgetData.userDefaultsKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Read widget data from shared App Group UserDefaults
    public func readWidgetData() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId),
              let data = defaults.data(forKey: WidgetData.userDefaultsKey),
              let widgetData = try? decoder.decode(WidgetData.self, from: data) else {
            return .empty
        }
        return widgetData
    }
}
