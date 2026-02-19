#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateLibraryView: View {
    @State private var viewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: TemplateViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.libraryTemplates) { template in
                    NavigationLink {
                        TemplateLibraryDetailView(template: template, viewModel: viewModel)
                    } label: {
                        LibraryTemplateRowView(
                            template: template,
                            isAdded: viewModel.isLibraryTemplateAdded(template)
                        )
                    }
                }
            }
            .navigationTitle("Template Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LibraryTemplateRowView: View {
    let template: WorkoutTemplate
    let isAdded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if isAdded {
                    Text("Added")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                Label("\(template.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notes = template.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
