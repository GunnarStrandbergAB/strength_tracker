#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ProgressionPlanCardView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    let proFeatureGate: ProFeatureGate?
    let storeService: StoreService?
    let onStartSession: (WorkoutTemplate, UUID, UUID, Bool) async -> Void
    @State private var showCreationSheet = false
    @State private var showActivePlanDetail = false
    @State private var showUpgradeSheet = false

    var body: some View {
        Group {
            if let plan = viewModel.activePlan, plan.isActive {
                activePlanCard(plan)
            } else if !viewModel.hasLoadedOnce {
                EmptyView()
            } else {
                noPlanCard
            }
        }
    }

    // MARK: - No Plan CTA

    private var isLocked: Bool {
        if let proFeatureGate {
            return !proFeatureGate.hasProAccess
        }
        return false
    }

    private var noPlanCard: some View {
        Button {
            if isLocked {
                showUpgradeSheet = true
            } else {
                showCreationSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isLocked ? "lock.fill" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22))
                    .foregroundStyle(isLocked ? STColors.textTertiary : STColors.success)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("CREATE TRAINING PLAN")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isLocked ? STColors.textTertiary : STColors.success)

                        if isLocked {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(STColors.background)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(STColors.primary)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Periodized programming with auto-progression")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                }

                Spacer()

                Image(systemName: isLocked ? "crown.fill" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isLocked ? STColors.primary : STColors.success.opacity(0.7))
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(isLocked ? STColors.primary.opacity(0.3) : STColors.success.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCreationSheet) {
            PlanCreationView(
                viewModel: viewModel,
                exerciseListViewModel: exerciseListViewModel,
                templateViewModel: templateViewModel
            )
        }
        .sheet(isPresented: $showUpgradeSheet) {
            if let storeService {
                ProUpgradeView(storeService: storeService)
            }
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
            ActivePlanDetailView(viewModel: viewModel, templateViewModel: templateViewModel, onStartSession: onStartSession)
        }
    }
}
#endif
