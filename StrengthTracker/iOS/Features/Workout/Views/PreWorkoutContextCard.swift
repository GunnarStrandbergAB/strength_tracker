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

            Text("\(ready.count) ready, \(recovering.count + fatigued.count) recovering")
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
                Text("Training Load")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(STColors.textSecondary)
                Text(String(format: "ACWR %.2f", load.acwr))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(loadZoneColor(load.loadZone))
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
                        .fill(loadZoneColor(load.loadZone))
                        .frame(width: width * fill, height: 6)
                }
            }
            .frame(width: 80, height: 6)

            Text(loadZoneLabel(load.loadZone))
                .font(.system(size: 11))
                .foregroundStyle(STColors.textSecondary)
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
                Text("This week")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)
                let weeklyTarget = Int(adherence.weeklyFrequency.rounded())
                Text("\(min(7, max(0, weeklyTarget))) typical")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(STColors.textPrimary)
            }

            if adherence.currentStreak > 1 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Streak")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                    Text("\(adherence.currentStreak) wk")
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
        switch status {
        case .ready: return STColors.success
        case .recovering: return Color.orange
        case .fatigued: return STColors.danger
        }
    }

    private func statusLabel(_ status: RecoveryStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .recovering: return "Recovering"
        case .fatigued: return "Fatigued"
        }
    }

    private func loadZoneColor(_ zone: LoadZone) -> Color {
        switch zone {
        case .underTraining: return .blue
        case .optimal: return STColors.success
        case .caution: return .orange
        case .danger: return STColors.danger
        }
    }

    private func loadZoneLabel(_ zone: LoadZone) -> String {
        switch zone {
        case .underTraining: return "Under"
        case .optimal: return "Optimal"
        case .caution: return "Caution"
        case .danger: return "Danger"
        }
    }
}

#endif
