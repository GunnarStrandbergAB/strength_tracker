import WidgetKit
import SwiftUI

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchRestTimerWidget()
        #if canImport(ActivityKit)
        WatchRestTimerLiveActivity()
        #endif
    }
}
