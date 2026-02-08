#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit
import StrengthTrackerShared

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / Banner presentation
            lockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.071, green: 0.071, blue: 0.071))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
                        Text("REST")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.formattedTime)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(Color(red: 0.949, green: 0.800, blue: 0.051))
                                    .frame(width: geo.size.width * context.state.progress, height: 6)
                            }
                        }
                        .frame(height: 6)

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
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
            } compactTrailing: {
                // Compact trailing
                Text(context.state.formattedTime)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
            } minimal: {
                // Minimal
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<RestTimerAttributes>) -> some View {
        HStack {
            // Left: Timer icon and label
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: 36, height: 36)

                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(
                            Color(red: 0.949, green: 0.800, blue: 0.051),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "timer")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("RESTING")
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

            // Right: Time remaining
            Text(context.state.formattedTime)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
        }
        .padding(16)
    }
}
#endif
