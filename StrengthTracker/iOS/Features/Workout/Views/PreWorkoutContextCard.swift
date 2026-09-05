#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PreWorkoutContextCard: View {
    let recoveryPatterns: [RecoveryPattern]
    let trainingLoad: TrainingLoad?
    let adherence: AdherenceAnalysis?
    let onStartWorkout: () -> Void
    let onStartFromPlan: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("READY TO TRAIN")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(STColors.primary)
                Spacer()
            }
            .padding(.horizontal, STSpacing.cardPadding)
            .padding(.top, STSpacing.cardPadding)
            .padding(.bottom, 12)

            // Recovery status
            if !recoveryPatterns.isEmpty {
                recoverySection
                Divider()
                    .background(STColors.border)
                    .padding(.horizontal, STSpacing.cardPadding)
            }

            // Training load gauge
            if let load = trainingLoad {
                loadSection(load)
                Divider()
                    .background(STColors.border)
                    .padding(.horizontal, STSpacing.cardPadding)
            }

            // Adherence summary
            if let adherence = adherence {
                adherenceSection(adherence)
            }

            // Start buttons
            VStack(spacing: 8) {
                Button(action: onStartWorkout) {
                    Text("START WORKOUT")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(STColors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(STColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if let onPlan = onStartFromPlan {
                    Button(action: onPlan) {
                        Text("START FROM PLAN")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(STColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(STSpacing.cardPadding)
        }
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Recovery Section

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery Status")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(STColors.textSecondary)

            let ready = recoveryPatterns.filter { $0.recoveryStatus == .ready }
            let recovering = recoveryPatterns.filter { $0.recoveryStatus == .recovering }
            let fatigued = recoveryPatterns.filter { $0.recoveryStatus == .fatigued }

            ForEach(recoveryPatterns.prefix(6), id: \.muscleGroup) { pattern in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(pattern.recoveryStatus))
                        .frame(width: 6, height: 6)
                    Text(pattern.muscleGroup.capitalized)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textPrimary)
                    Spacer()
                    Text(statusLabel(pattern.recoveryStatus))
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                }
            }

            Text("\(ready.count) ready · \(recovering.count) recovering · \(fatigued.count) fatigued")
                .font(.system(size: 11))
                .foregroundStyle(STColors.textTertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, STSpacing.cardPadding)
        .padding(.bottom, 12)
    }

    // MARK: - Load Section

    private func loadSection(_ load: TrainingLoad) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Training load")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(STColors.textSecondary)
                Text("ACWR \(AnalyticsFormatting.acwr(load.acwr)) · \(AnalyticsFormatting.loadZoneLabel(load.loadZone))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AnalyticsColors.zone(load.loadZone))
            }

            Spacer()

            // Simple gauge bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let fill = min(1.0, load.acwr / 2.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(STColors.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AnalyticsColors.zone(load.loadZone))
                        .frame(width: width * fill, height: 6)
                }
            }
            .frame(width: 80, height: 6)

        }
        .padding(.horizontal, STSpacing.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Adherence Section

    private func adherenceSection(_ adherence: AdherenceAnalysis) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last workout")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)
                Text("\(adherence.currentGapDays) day\(adherence.currentGapDays == 1 ? "" : "s") ago")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(STColors.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Usual pace")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)
                let weeklyTarget = Int(adherence.weeklyFrequency.rounded())
                Text("\(min(7, max(0, weeklyTarget)))×/week")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(STColors.textPrimary)
            }

            if adherence.currentStreak > 1 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Rhythm")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                    Text(AnalyticsFormatting.streak(weeks: adherence.currentStreak))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(STColors.primary)
                }
            }
        }
        .padding(.horizontal, STSpacing.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func statusColor(_ status: RecoveryStatus) -> Color {
        AnalyticsColors.recovery(status)
    }

    private func statusLabel(_ status: RecoveryStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .recovering: return "Recovering"
        case .fatigued: return "Fatigued"
        }
    }

}

#endif
