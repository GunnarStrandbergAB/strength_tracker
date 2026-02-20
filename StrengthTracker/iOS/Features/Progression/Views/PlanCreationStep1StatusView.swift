#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep1StatusView: View {
    let viewModel: ProgressionPlanViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 1 of 4")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STColors.primary)

                    Text("Training Level")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)

                    Text("We'll detect your level from workout history, or you can choose manually.")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Detection status
                if viewModel.draftStatusIsDetecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(STColors.primary)
                        Text("Analyzing workout history...")
                            .font(.system(size: 13))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }

                // Status options
                VStack(spacing: 10) {
                    ForEach(TrainingStatus.allCases, id: \.self) { status in
                        statusRow(status)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            continueButton
        }
        .task {
            await viewModel.detectTrainingStatus()
        }
    }

    private func statusRow(_ status: TrainingStatus) -> some View {
        Button {
            viewModel.draftStatus = status
            viewModel.applyStatusRecommendation()
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                Circle()
                    .fill(viewModel.draftStatus == status ? STColors.primary : Color.clear)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(viewModel.draftStatus == status ? STColors.primary : STColors.textTertiary, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.rawValue.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)

                    Text(status.progressionRate)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)

                    Text("Recommended: \(status.recommendedProgramType.displayName)")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }

                Spacer()
            }
            .padding(14)
            .background(viewModel.draftStatus == status ? STColors.primary.opacity(0.08) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(viewModel.draftStatus == status ? STColors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            viewModel.draftStep = 2
        } label: {
            Text("Continue")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(STColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(STColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(STColors.background)
    }
}
#endif
