#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep3ExercisesView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    @State private var showExercisePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 3 of 4")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STColors.primary)

                    Text("Select Exercises")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)

                    Text("Choose exercises and enter your estimated 1RM for each.")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Selected exercises
                if viewModel.draftSelectedExercises.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.draftSelectedExercises) { draft in
                            exerciseRow(draft)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Add button
                Button {
                    showExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Add Exercise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(STColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(STColors.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: STRadius.card)
                            .stroke(STColors.primary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            navigationButtons
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                viewModel.addExercise(exercise)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.system(size: 28))
                .foregroundStyle(STColors.textTertiary)

            Text("No exercises selected")
                .font(.system(size: 14))
                .foregroundStyle(STColors.textSecondary)

            Text("Add at least 1 exercise to continue")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Exercise Row

    private func exerciseRow(_ draft: DraftPlanExercise) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.exercise.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)
                    .lineLimit(1)

                Text(draft.exercise.primaryMuscleGroup.rawValue.capitalized)
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
            }

            Spacer()

            // 1RM input
            HStack(spacing: 4) {
                TextField("1RM", value: Binding(
                    get: { draft.oneRM == 0 ? nil : draft.oneRM },
                    set: { newVal in
                        viewModel.updateOneRM(for: draft.id, value: newVal ?? 0)
                    }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .default))
                .frame(width: 60)
                .foregroundStyle(STColors.textPrimary)

                Text("kg")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(STColors.background)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.input))

            // Remove button
            Button {
                viewModel.removeExercise(id: draft.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(STColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .task {
            await viewModel.loadOneRMEstimate(for: draft)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.draftStep = 2
            } label: {
                Text("Back")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(STColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                viewModel.draftStep = 4
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(STColors.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(viewModel.draftSelectedExercises.isEmpty ? STColors.textTertiary : STColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.draftSelectedExercises.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(STColors.background)
    }
}
#endif
