#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct WeeklyDigestCard: View {
    let digest: WeeklyDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("LAST WEEK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(STColors.textTertiary)
                Spacer()
                Text(weekSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
            }

            // Stats row
            HStack(spacing: 16) {
                statBadge(
                    value: "\(digest.workoutsLastWeek)",
                    label: "workouts"
                )
                if abs(digest.volumeDeltaPercent) > 1 {
                    statBadge(
                        value: String(format: "%+.0f%%", digest.volumeDeltaPercent),
                        label: "volume"
                    )
                }
                if digest.prsThisWeek > 0 {
                    statBadge(
                        value: "\(digest.prsThisWeek)",
                        label: digest.prsThisWeek == 1 ? "PR" : "PRs"
                    )
                }
            }

            // Top insight
            HStack(spacing: 8) {
                Image(systemName: digest.topInsight.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(insightColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(digest.topInsight.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)
                    Text(digest.topInsight.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
    }

    private var weekSummary: String {
        let delta = digest.workoutsThisWeek - digest.workoutsLastWeek
        if delta > 0 {
            return "\(digest.workoutsThisWeek) so far this week (+\(delta))"
        } else if delta < 0 {
            return "\(digest.workoutsThisWeek) so far this week (\(delta))"
        }
        return "\(digest.workoutsThisWeek) so far this week"
    }

    private var insightColor: Color {
        switch digest.topInsight.color {
        case .primary: return STColors.primary
        case .success: return STColors.success
        case .warning: return Color.orange
        case .danger: return STColors.danger
        case .info: return .blue
        }
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(STColors.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(STColors.textTertiary)
        }
    }
}

#endif
