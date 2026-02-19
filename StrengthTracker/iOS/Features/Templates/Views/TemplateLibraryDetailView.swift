#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateLibraryDetailView: View {
    let template: WorkoutTemplate
    @State private var viewModel: TemplateViewModel
    @State private var justAdded = false
    @Environment(\.dismiss) private var dismiss

    init(template: WorkoutTemplate, viewModel: TemplateViewModel) {
        self.template = template
        self._viewModel = State(initialValue: viewModel)
    }

    private var isAdded: Bool {
        justAdded || viewModel.isLibraryTemplateAdded(template)
    }

    var body: some View {
        List {
            Section {
                if let notes = template.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                    Spacer()
                    Text("\(template.exercises.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                ForEach(template.exercises.sorted(by: { $0.order < $1.order })) { templateExercise in
                    LibraryExerciseRowView(templateExercise: templateExercise)
                }
            }

            Section {
                Button {
                    Task {
                        await viewModel.addLibraryTemplate(template)
                        justAdded = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isAdded {
                            Label("Added to My Templates", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                        } else {
                            Label("Add to My Templates", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isAdded)
                .buttonStyle(.borderedProminent)
                .tint(isAdded ? .gray : .blue)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LibraryExerciseRowView: View {
    let templateExercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(templateExercise.exercise.name)
                .font(.body)
                .fontWeight(.medium)

            Text(targetSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var targetSummary: String {
        let te = templateExercise
        var parts: [String] = ["\(te.targetSets) sets"]
        if let reps = te.targetReps { parts.append("\(reps) reps") }
        if let rest = te.restTimerSeconds { parts.append("\(rest)s rest") }
        return parts.joined(separator: " \u{00B7} ")
    }
}
#endif
