#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

@main
struct StrengthTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutSummaryWidget()
        WeeklyProgressWidget()
        TrainingHubWidget()
        #if os(iOS)
        if #available(iOS 16.1, *) {
            StreakAccessoryWidget()
        }
        // Live Activity for rest timer
        if #available(iOS 16.2, *) {
            RestTimerLiveActivity()
        }
        #endif
    }
}
#endif
