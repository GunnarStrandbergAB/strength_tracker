#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct WeeklyFrequencyChart: View {
    let weeklyWorkoutCounts: [Int]
    let totalWorkouts: Int
    let trend: Double
    let trendIsPositive: Bool
    let formattedTrend: String

    private let dayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: title + trend badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY FREQUENCY")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(STColors.textSecondary)
                        .tracking(0.8)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(totalWorkouts)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        Text("WORKOUTS")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(STColors.textTertiary)
                    }
                }

                Spacer()

                if trend != 0 {
                    TrendBadge(
                        value: formattedTrend,
                        isPositive: trendIsPositive
                    )
                }
            }
            .padding(.bottom, 20)

            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 8) {
                        BarView(
                            value: weeklyWorkoutCounts[index],
                            maxValue: maxCount
                        )
                        .frame(height: 96)

                        Text(dayLabels[index])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(STColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var maxCount: Int {
        max(weeklyWorkoutCounts.max() ?? 1, 1)
    }
}

// MARK: - Bar View

private struct BarView: View {
    let value: Int
    let maxValue: Int

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let fillFraction = value > 0 ? CGFloat(value) / CGFloat(maxValue) : 0
            let fillHeight = totalHeight * fillFraction
            let minFillHeight: CGFloat = value > 0 ? 8 : 0

            ZStack(alignment: .bottom) {
                // Background bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(STColors.border.opacity(0.5))
                    .frame(height: totalHeight)

                // Filled portion
                if value > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(STColors.primary)
                        .frame(height: max(fillHeight, minFillHeight))
                }
            }
        }
    }
}

// MARK: - Trend Badge

private struct TrendBadge: View {
    let value: String
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .bold))

            Text(value)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(isPositive ? STColors.success : STColors.danger)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (isPositive ? STColors.success : STColors.danger)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }
}

#endif
