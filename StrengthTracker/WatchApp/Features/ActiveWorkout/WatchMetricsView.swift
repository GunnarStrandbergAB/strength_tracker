#if canImport(SwiftUI) && os(watchOS)
import SwiftUI

struct WatchMetricsView: View {
    let heartRate: Double
    let activeCalories: Double
    let elapsedTime: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            // Heart rate
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                Text(heartRate > 0 ? "\(Int(heartRate))" : "--")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            // Calories
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(activeCalories > 0 ? "\(Int(activeCalories))" : "--")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            // Duration
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text(formatDuration(elapsedTime))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
