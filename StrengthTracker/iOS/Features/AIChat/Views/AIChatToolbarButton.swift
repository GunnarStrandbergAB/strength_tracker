#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Everything a screen needs to offer the assistant. Built once in ContentView.
@MainActor
struct AIChatEntry {
    let viewModel: AIChatViewModel
    let userPreferencesService: UserPreferencesService
    let credentials: AICredentialsService

    var isAvailable: Bool {
        userPreferencesService.aiChatEnabled && credentials.hasKey
    }
}

/// The sparkles button that opens the assistant.
struct AIChatToolbarButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(STColors.primary)
                .frame(width: 36, height: 36)
                .background(STColors.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Assistant")
    }
}

extension View {
    /// Presents the assistant as a full-screen cover. Attach to the screen root,
    /// not a toolbar item (presentation modifiers on toolbar items are unreliable).
    func aiChatCover(_ entry: AIChatEntry?, isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            if let entry {
                AIChatView(
                    viewModel: entry.viewModel,
                    userPreferencesService: entry.userPreferencesService
                )
            }
        }
    }
}
#endif
