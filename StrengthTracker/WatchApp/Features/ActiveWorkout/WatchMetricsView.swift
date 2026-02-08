#if canImport(SwiftUI) && os(watchOS)
import SwiftUI

struct WatchMetricsView: View {
    let heartRate: Double
    let activeCalories: Double
    let elapsedTime: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            // Heart rate
            metricItem(
                icon: "heart.fill",
                value: heartRate > 0 ? "\(Int(heartRate))" : "--",
                unit: "BPM",
                color: .red
            )

            // Calories
            metricItem(
                icon: "flame.fill",
                value: activeCalories > 0 ? "\(Int(activeCalories))" : "--",
                unit: "CAL",
                color: .orange
            )

            // Duration
            metricItem(
                icon: "timer",
                value: formatDuration(elapsedTime),
                unit: "",
                color: .green
            )
        }
        .padding(.vertical, 4)
    }

    private func metricItem(icon: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
