#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit
import StrengthTrackerShared

struct WatchRestTimerLiveActivity: Widget {
    private static let accentColor = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // watchOS renders .small (Smart Stack); iOS renders .medium (Lock Screen)
            WatchLiveActivitySmartStackView(context: context)
                .activityBackgroundTint(Color(red: 0.071, green: 0.071, blue: 0.071))
        } dynamicIsland: { context in
            // Dynamic Island is iOS-only; required by compiler but never used on watchOS
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(Self.accentColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.timerRange, countsDown: true)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Self.accentColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.exerciseName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Self.accentColor)
            } compactTrailing: {
                Text(timerInterval: context.state.timerRange, countsDown: true)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Self.accentColor)
            }
        }
    }
}

// MARK: - watchOS Smart Stack layout

private struct WatchLiveActivitySmartStackView: View {
    let context: ActivityViewContext<RestTimerAttributes>
    private static let accentColor = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if !context.isStale {
                        ProgressView(timerInterval: context.state.timerRange, countsDown: true)
                            .progressViewStyle(.circular)
                            .tint(Self.accentColor)
                            .frame(width: 24, height: 24)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.isStale ? "DONE" : "RESTING")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(context.attributes.exerciseName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            Spacer()

            if context.isStale {
                Text("00:00")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
            } else {
                Text(timerInterval: context.state.timerRange, countsDown: true)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
            }
        }
        .padding(10)
        .widgetURL(URL(string: "strengthtracker://workout"))
    }
}
#endif
