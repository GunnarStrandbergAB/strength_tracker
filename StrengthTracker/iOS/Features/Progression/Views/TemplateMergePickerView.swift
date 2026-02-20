#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateMergePickerView: View {
    let session: PlannedSession
    let planId: UUID
    let templateViewModel: TemplateViewModel
    let progressionPlanViewModel: ProgressionPlanViewModel
    let onStartSession: (WorkoutTemplate, UUID, UUID) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Group {
                if templateViewModel.templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.clipboard",
                        description: Text("Create a workout template first.")
                    )
                } else {
                    List {
                        ForEach(templateViewModel.templates) { template in
                            let matchCount = countMatches(template: template)
                            Button {
                                Task {
                                    isStarting = true
                                    let merged = progressionPlanViewModel.mergeSessionIntoTemplate(
                                        session: session, template: template
                                    )
                                    await onStartSession(merged, session.id, planId)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(STColors.textPrimary)

                                        Text("\(template.exercises.count) exercises, \(matchCount) matching plan")
                                            .font(.system(size: 12))
                                            .foregroundStyle(STColors.textSecondary)
                                    }

                                    Spacer()

                                    if matchCount > 0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(STColors.success)
                                    }
                                }
                            }
                            .disabled(isStarting)
                        }
                    }
                }
            }
            .navigationTitle("Pick Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            await templateViewModel.loadTemplates()
        }
    }

    private func countMatches(template: WorkoutTemplate) -> Int {
        let plannedIds = Set(session.plannedExercises.map(\.exerciseId))
        return template.exercises.filter { plannedIds.contains($0.exercise.id) }.count
    }
}
#endif
