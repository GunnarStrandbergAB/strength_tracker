#if canImport(SwiftUI)
import SwiftUI
import Observation
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

struct AIChatPresentation: Identifiable {
    let id = UUID()
    let entry: AIChatEntry
}

struct WorkoutSummaryPresentation: Identifiable {
    let id = UUID()
    let debrief: PostWorkoutDebrief
    let weightUnit: WeightUnit
}

/// The root owns both presentations. Occupancy lasts through onDismiss, not just
/// until SwiftUI sets an item to nil at the start of the closing animation.
@MainActor @Observable
final class AppPresentationState {
    var chat: AIChatPresentation?
    var summary: WorkoutSummaryPresentation?
    private(set) var chatIsOccupied = false
    private(set) var summaryIsOccupied = false
    private(set) var isPreparingChat = false
    private var pendingSummaries: [WorkoutSummaryPresentation] = []

    func openChat(_ entry: AIChatEntry) async {
        guard entry.isAvailable, !chatIsOccupied, !summaryIsOccupied, !isPreparingChat else { return }
        isPreparingChat = true
        defer { isPreparingChat = false; presentNextSummary() }
        guard await AppKeyboardDismissal.commitAndDismiss(), entry.isAvailable else { return }
        chatIsOccupied = true
        chat = AIChatPresentation(entry: entry)
    }

    func enqueueSummary(_ debrief: PostWorkoutDebrief, weightUnit: WeightUnit) {
        pendingSummaries.append(.init(debrief: debrief, weightUnit: weightUnit))
        presentNextSummary()
    }

    func chatDidDismiss() {
        chat = nil
        chatIsOccupied = false
        presentNextSummary()
    }

    func summaryDidDismiss() {
        summary = nil
        summaryIsOccupied = false
        presentNextSummary()
    }

    private func presentNextSummary() {
        guard !chatIsOccupied, !summaryIsOccupied, !isPreparingChat, !pendingSummaries.isEmpty else { return }
        summaryIsOccupied = true
        summary = pendingSummaries.removeFirst()
    }
}

struct AppPresentations: ViewModifier {
    @Bindable var state: AppPresentationState

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $state.chat, onDismiss: state.chatDidDismiss) { presentation in
            AIChatView(viewModel: presentation.entry.viewModel,
                userPreferencesService: presentation.entry.userPreferencesService)
        }
        .sheet(item: $state.summary, onDismiss: state.summaryDidDismiss) { presentation in
            PostWorkoutSummaryView(debrief: presentation.debrief, weightUnit: presentation.weightUnit) {
                state.summary = nil
            }
            .preferredColorScheme(.dark)
        }
    }
}
#endif
