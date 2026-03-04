#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.draftStep {
                case 1:
                    PlanCreationStep1StatusView(viewModel: viewModel)
                case 2:
                    PlanCreationStep2GoalView(viewModel: viewModel)
                case 3:
                    PlanCreationStep3ExercisesView(
                        viewModel: viewModel,
                        exerciseListViewModel: exerciseListViewModel
                    )
                case 4:
                    PlanCreationStep4ScheduleView(
                        viewModel: viewModel,
                        templateViewModel: templateViewModel
                    )
                case 5:
                    PlanCreationStep5ReviewView(viewModel: viewModel) {
                        viewModel.resetDraft()
                        dismiss()
                    }
                default:
                    EmptyView()
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetDraft()
                        dismiss()
                    }
                    .foregroundStyle(STColors.textSecondary)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSavingPlan)
    }
}
#endif
