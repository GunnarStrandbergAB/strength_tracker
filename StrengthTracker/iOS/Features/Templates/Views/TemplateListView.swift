#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateListView: View {
    @State private var viewModel: TemplateViewModel
    @State private var showingEditor = false

    init(viewModel: TemplateViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.templates) { template in
                    NavigationLink(value: template) {
                        TemplateRowView(template: template)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let template = viewModel.templates[index]
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
                TemplateDetailView(template: template, viewModel: viewModel)
            }
            .sheet(isPresented: $showingEditor) {
                TemplateEditorView(viewModel: viewModel, template: nil)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.templates.isEmpty {
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
