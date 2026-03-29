#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PostWorkoutSummaryView: View {
    let debrief: PostWorkoutDebrief
    let onDismiss: () -> Void

    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                checkmarkHeader
                statsSection
                qualityScoreSection
                bulletsSection
                dismissButton
            }
            .padding(24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(STColors.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                showContent = true
            }
        }
    }

    // MARK: - Header

    private var checkmarkHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(STColors.primary)
                .scaleEffect(showContent ? 1.0 : 0.3)
                .opacity(showContent ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showContent)

            Text("Workout Done")
                .font(.title2.bold())
                .foregroundStyle(STColors.textPrimary)
                .opacity(showContent ? 1.0 : 0.0)
        }
        .padding(.top, 16)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 8) {
            Text(debrief.workoutName)
                .font(.headline)
                .foregroundStyle(STColors.textPrimary)

            HStack(spacing: 16) {
                statPill(label: formatDuration(debrief.duration), icon: "clock")
                statPill(label: "\(debrief.exerciseCount) exercises", icon: "dumbbell")
                statPill(label: "\(debrief.totalSets) sets", icon: "number")
            }

            Text("Total: \(formatVolume(debrief.totalVolume)) kg")
                .font(.subheadline)
                .foregroundStyle(STColors.textSecondary)

            if debrief.prsHit > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(STColors.primary)
                    Text("\(debrief.prsHit) PR\(debrief.prsHit > 1 ? "s" : "")")
                        .font(.caption.bold())
                        .foregroundStyle(STColors.primary)
                }
            }
        }
        .opacity(showContent ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.4).delay(0.3), value: showContent)
    }

    private func statPill(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(STColors.textSecondary)
    }

    // MARK: - Quality Score

    @ViewBuilder
    private var qualityScoreSection: some View {
        if let score = debrief.qualityScore {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(STColors.border, lineWidth: 6)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: showContent ? score.overallScore / 100.0 : 0)
                        .stroke(
                            scoreColor(score.overallScore),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8).delay(0.5), value: showContent)

                    Text(String(format: "%.0f", score.overallScore))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(STColors.textPrimary)
                }

                Text("Quality Score")
                    .font(.caption)
                    .foregroundStyle(STColors.textSecondary)
            }
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.4).delay(0.4), value: showContent)
        }
    }

    // MARK: - Coaching Bullets

    @ViewBuilder
    private var bulletsSection: some View {
        if !debrief.bullets.isEmpty {
            VStack(spacing: 12) {
                ForEach(Array(debrief.bullets.enumerated()), id: \.element.id) { index, bullet in
                    bulletRow(bullet)
                        .opacity(showContent ? 1.0 : 0.0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.5 + Double(index) * 0.15), value: showContent)
                }
            }
        }
    }

    private func bulletRow(_ insight: CoachingInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.system(size: 16))
                .foregroundStyle(colorForCoaching(insight.color))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(STColors.textPrimary)
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(STColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Got It")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(STColors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(STColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(showContent ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.4).delay(0.8), value: showContent)
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) min"
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return STColors.success
        case 60..<80: return STColors.primary
        default: return STColors.danger
        }
    }

    private func colorForCoaching(_ color: CoachingColor) -> Color {
        switch color {
        case .primary: return STColors.primary
        case .success: return STColors.success
        case .warning: return Color.orange
        case .danger: return STColors.danger
        case .info: return STColors.textSecondary
        }
    }
}
#endif
