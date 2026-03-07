import WidgetKit
import SwiftUI

@main
struct StrengthTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutSummaryWidget()
        WeeklyProgressWidget()
        TrainingHubWidget()
        StreakAccessoryWidget()
        RestTimerLiveActivity()
    }
}
