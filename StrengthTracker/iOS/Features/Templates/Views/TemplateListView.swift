#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateListView: View {
    @State private var viewModel: TemplateViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let workoutViewModel: WorkoutViewModel
    @State private var showingEditor = false
    @State private var showingLibrary = false

    init(viewModel: TemplateViewModel, exerciseListViewModel: ExerciseListViewModel, workoutViewModel: WorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self.exerciseListViewModel = exerciseListViewModel
        self.workoutViewModel = workoutViewModel
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.libraryTemplates.isEmpty {
                    Section {
                        Button {
                            showingLibrary = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.full.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Browse Library")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text("\(viewModel.libraryTemplates.count) pre-built templates")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                ForEach(viewModel.userTemplates) { template in
                    NavigationLink(value: template) {
                        TemplateRowView(template: template)
                    }
                }
                .onDelete { indexSet in
                    let userList = viewModel.userTemplates
                    for index in indexSet {
                        let template = userList[index]
                        Task {
                            await viewModel.deleteTemplate(template)
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("New Template", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: WorkoutTemplate.self) { template in
                TemplateDetailView(template: template, viewModel: viewModel, exerciseListViewModel: exerciseListViewModel, workoutViewModel: workoutViewModel)
            }
            .sheet(isPresented: $showingEditor, onDismiss: {
                Task { await viewModel.loadTemplates() }
            }) {
                TemplateEditorView(viewModel: viewModel, exerciseListViewModel: exerciseListViewModel, template: nil)
            }
            .sheet(isPresented: $showingLibrary, onDismiss: {
                Task { await viewModel.loadTemplates() }
            }) {
                TemplateLibraryView(viewModel: viewModel)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.userTemplates.isEmpty && viewModel.libraryTemplates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "doc.text",
                        description: Text("Create a template to quickly start workouts with preset exercises.")
                    )
                }
            }
            .task {
                await viewModel.loadTemplates()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

private struct TemplateRowView: View {
    let template: WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                Label("\(template.exercises.count)", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastUsed = template.lastUsedAt {
                    Text("Last used: \(lastUsed, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if template.timesUsed > 0 {
                    Text("\(template.timesUsed) times")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
