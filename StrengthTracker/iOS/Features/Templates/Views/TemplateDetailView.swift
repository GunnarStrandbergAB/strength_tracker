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
            TemplateEditorView(viewModel: viewModel, exerciseListViewModel: exerciseListViewModel, template: template, workoutViewModel: workoutViewModel)
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

            Text(detailTargetsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let notes = templateExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailTargetsSummary: String {
        let te = templateExercise
        let targets = te.setTargets
        let sets = te.targetSets

        guard !targets.isEmpty else {
            var parts: [String] = ["\(sets) sets"]
            if let reps = te.targetReps { parts.append("\(reps) reps") }
            if let w = te.targetWeight { parts.append("\(detailFormatWeight(w)) kg") }
            if let d = te.targetDurationSeconds { parts.append("\(d)s") }
            if let dist = te.targetDistanceMeters { parts.append("\(Int(dist))m") }
            return parts.joined(separator: " \u{00B7} ")
        }

        let weights = targets.compactMap(\.targetWeight)
        let reps = targets.compactMap(\.targetReps)
        let durations = targets.compactMap(\.targetDurationSeconds)
        let distances = targets.compactMap(\.targetDistanceMeters)

        var result = "\(sets)"

        if !reps.isEmpty {
            let allSame = Set(reps).count == 1
            let repsStr = allSame ? "\(reps[0])" : reps.map { String($0) }.joined(separator: "/")
            result += "\u{00D7}\(repsStr)"
        }

        if !weights.isEmpty {
            let allSame = Set(weights).count == 1
            let wStr = allSame ? detailFormatWeight(weights[0]) : weights.map { detailFormatWeight($0) }.joined(separator: "/")
            result += " @ \(wStr) kg"
        }

        if !durations.isEmpty && weights.isEmpty {
            let allSame = Set(durations).count == 1
            let dStr = allSame ? "\(durations[0])" : durations.map { String($0) }.joined(separator: "/")
            result += " \u{00D7} \(dStr)s"
        }

        if !distances.isEmpty && weights.isEmpty {
            let allSame = Set(distances).count == 1
            let distStr = allSame ? "\(Int(distances[0]))" : distances.map { String(Int($0)) }.joined(separator: "/")
            result += " \u{00D7} \(distStr)m"
        }

        return result
    }

    private func detailFormatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }
}
#endif
