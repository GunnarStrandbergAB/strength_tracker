#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit
import StrengthTrackerShared

struct RestTimerLiveActivity: Widget {
    private static let accentColor = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / Banner / watchOS Smart Stack presentation
            if #available(iOSApplicationExtension 18.0, *) {
                RestTimerAdaptiveContentView(context: context)
                    .activityBackgroundTint(Color(red: 0.071, green: 0.071, blue: 0.071))
            } else {
                RestTimerLockScreenView(context: context)
                    .activityBackgroundTint(Color(red: 0.071, green: 0.071, blue: 0.071))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 14))
                            .foregroundStyle(Self.accentColor)
                        Text("REST")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale {
                        Text("00:00")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Self.accentColor)
                    } else {
                        Text(timerInterval: context.state.timerRange, countsDown: true)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Self.accentColor)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if !context.isStale {
                            ProgressView(timerInterval: context.state.timerRange, countsDown: true)
                                .tint(Self.accentColor)
                        }

                        HStack {
                            Text(context.attributes.exerciseName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Set \(context.attributes.setNumber)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Compact leading
                Label {
                    Text(context.attributes.exerciseName)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.accentColor)
            } compactTrailing: {
                // Compact trailing
                Text(timerInterval: context.state.timerRange, countsDown: true)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
                    .frame(minWidth: 36)
            } minimal: {
                // Minimal
                ProgressView(timerInterval: context.state.timerRange, countsDown: true) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(Self.accentColor)
                }
                .progressViewStyle(.circular)
                .tint(Self.accentColor)
            }
        }
        .supplementalActivityFamiliesIfAvailable()
    }

}

// MARK: - Adaptive Content View (iOS 18+ with activityFamily support)

@available(iOSApplicationExtension 18.0, *)
private struct RestTimerAdaptiveContentView: View {
    @Environment(\.activityFamily) var activityFamily
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            RestTimerSmartStackView(context: context)
        case .medium:
            RestTimerLockScreenView(context: context)
        @unknown default:
            RestTimerLockScreenView(context: context)
        }
    }
}

// MARK: - watchOS Smart Stack layout (.small)

private struct RestTimerSmartStackView: View {
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

// MARK: - iPhone Lock Screen layout (.medium)

private struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>
    private static let accentColor = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: 36, height: 36)

                    if !context.isStale {
                        ProgressView(timerInterval: context.state.timerRange, countsDown: true)
                            .progressViewStyle(.circular)
                            .tint(Self.accentColor)
                            .frame(width: 36, height: 36)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.isStale ? "DONE" : "RESTING")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(context.attributes.exerciseName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            Spacer()

            if context.isStale {
                Text("00:00")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
            } else {
                Text(timerInterval: context.state.timerRange, countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accentColor)
            }
        }
        .padding(16)
    }
}

extension ActivityConfiguration {
    /// Apply `.supplementalActivityFamilies([.small])` on iOS 18+ to mirror
    /// the Live Activity to the watchOS Smart Stack, falling back to the
    /// unmodified configuration on earlier versions.
    func supplementalActivityFamiliesIfAvailable() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 18.0, *) {
            return self.supplementalActivityFamilies([.small])
        } else {
            return self
        }
    }
}
#endif
