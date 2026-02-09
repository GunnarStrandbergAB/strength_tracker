#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateDetailView: View {
    private let templateId: UUID
    private let initialTemplate: WorkoutTemplate
    @State private var viewModel: TemplateViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let workoutViewModel: WorkoutViewModel
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    /// Always returns the latest version from the viewModel (refreshed on sheet dismiss)
    private var template: WorkoutTemplate {
        viewModel.templates.first { $0.id == templateId } ?? initialTemplate
    }

    init(template: WorkoutTemplate, viewModel: TemplateViewModel, exerciseListViewModel: ExerciseListViewModel, workoutViewModel: WorkoutViewModel) {
        self.templateId = template.id
        self.initialTemplate = template
        self._viewModel = State(initialValue: viewModel)
        self.exerciseListViewModel = exerciseListViewModel
        self.workoutViewModel = workoutViewModel
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

                if template.timesUsed > 0 {
                    HStack {
                        Label("Times Used", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(template.timesUsed)")
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastUsed = template.lastUsedAt {
                    HStack {
                        Label("Last Used", systemImage: "clock")
                        Spacer()
                        Text(lastUsed, style: .date)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Exercises") {
                ForEach(template.exercises.sorted(by: { $0.order < $1.order })) { templateExercise in
                    TemplateExerciseRowView(templateExercise: templateExercise)
                }
            }

            Section {
                Button {
                    Task {
                        await workoutViewModel.startWorkout(name: template.name, from: template)
                        dismiss()
                    }
                } label: {
                    Label("Start Workout", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete Template?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteTemplate(template)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently delete \"\(template.name)\". This cannot be undone.")
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            Task { await viewModel.loadTemplates() }
        }) {
            TemplateEditorView(viewModel: viewModel, exerciseListViewModel: exerciseListViewModel, template: template)
        }
    }
}

private struct TemplateExerciseRowView: View {
    let templateExercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(templateExercise.exercise.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let supersetGroup = templateExercise.supersetGroup {
                    Text("SS\(supersetGroup)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                Label("\(templateExercise.targetSets) sets", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reps = templateExercise.targetReps {
                    Label("\(reps) reps", systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let weight = templateExercise.targetWeight {
                    Label("\(weight, specifier: "%.1f") kg", systemImage: "scalemass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duration = templateExercise.targetDurationSeconds {
                    Label("\(duration)s", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let distance = templateExercise.targetDistanceMeters {
                    Label("\(distance, specifier: "%.0f")m", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let notes = templateExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
