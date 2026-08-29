#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Manage the facts Grok has saved about the user.
struct AIMemoriesView: View {
    let memoryService: AIMemoryService
    @State private var showClearConfirmation = false

    var body: some View {
        Group {
            if memoryService.memories.isEmpty {
                ContentUnavailableView(
                    "No Memories",
                    systemImage: "brain",
                    description: Text("Grok hasn't saved any memories yet — ask it to remember something about you.")
                )
            } else {
                List {
                    Section {
                        ForEach(memoryService.memories.sorted(by: { $0.createdAt > $1.createdAt })) { memory in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.text)
                                    .font(.system(size: 15))
                                Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(STColors.textTertiary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    memoryService.remove(id: memory.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Grok reads these at the start of every new conversation. Saved on this device only.")
                    }
                }
            }
        }
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
        .toolbar {
            if !memoryService.memories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(STColors.danger)
                }
            }
        }
        .confirmationDialog(
            "Delete all memories?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                memoryService.removeAll()
            }
        } message: {
            Text("Grok will forget everything it has learned about you.")
        }
    }
}
#endif
