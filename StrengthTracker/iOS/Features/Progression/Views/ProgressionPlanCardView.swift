#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ProgressionPlanCardView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let onStartSession: (WorkoutTemplate) async -> Void
    @State private var showCreationSheet = false
    @State private var showActivePlanDetail = false

    var body: some View {
        Group {
            if let plan = viewModel.activePlan, plan.isActive {
                activePlanCard(plan)
            } else {
                noPlanCard
            }
        }
    }

    // MARK: - No Plan CTA

    private var noPlanCard: some View {
        Button {
            showCreationSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22))
                    .foregroundStyle(STColors.success)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CREATE TRAINING PLAN")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(STColors.success)

                    Text("Periodized programming with auto-progression")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(STColors.success.opacity(0.7))
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.success.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCreationSheet) {
            PlanCreationView(
                viewModel: viewModel,
                exerciseListViewModel: exerciseListViewModel
            )
        }
    }

    // MARK: - Active Plan Card

    private func activePlanCard(_ plan: ProgressionPlan) -> some View {
        Button {
            showActivePlanDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TRAINING PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(STColors.textSecondary)

                    Spacer()

                    Text(plan.programType.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(STColors.primary.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(plan.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)

                if let blockName = viewModel.currentBlockName,
                   let weekNum = viewModel.currentWeekNumber {
                    Text("\(blockName) \u{2022} Week \(weekNum)")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(STColors.background)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(STColors.primary)
                            .frame(width: geo.size.width * plan.overallProgress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(viewModel.adherencePercent)% adherence")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)

                    Spacer()

                    if let session = viewModel.nextSessionLabel {
                        Text("Next: \(session)")
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: $showActivePlanDetail) {
            ActivePlanDetailView(viewModel: viewModel, onStartSession: onStartSession)
        }
    }
}
#endif
