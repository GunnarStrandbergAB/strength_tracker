#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateMergePickerView: View {
    let session: PlannedSession
    let planExercises: [PlanExercise]
    let templateViewModel: TemplateViewModel
    let progressionPlanViewModel: ProgressionPlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLinking = false

    var body: some View {
        NavigationStack {
            Group {
                if templateViewModel.userTemplates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.clipboard",
                        description: Text("Create a workout template first.")
                    )
                } else {
                    List {
                        ForEach(templateViewModel.userTemplates) { template in
                            let matchCount = countMatches(template: template)
                            let isAlreadyLinked = session.templateId == template.id
                            Button {
                                Task {
                                    isLinking = true
                                    await progressionPlanViewModel.linkTemplate(
                                        templateId: template.id, toSession: session.id
                                    )
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

                                    if isAlreadyLinked {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(STColors.primary)
                                    } else if matchCount > 0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(STColors.success)
                                    }
                                }
                            }
                            .disabled(isLinking)
                        }
                    }
                }
            }
            .navigationTitle("Link Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await templateViewModel.loadTemplates()
        }
    }

    private func countMatches(template: WorkoutTemplate) -> Int {
        PlanExercise.matchCount(template: template, planExercises: planExercises)
    }
}
#endif
