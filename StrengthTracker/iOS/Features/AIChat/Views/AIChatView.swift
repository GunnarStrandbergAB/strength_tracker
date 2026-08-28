#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct AIChatView: View {
    let viewModel: AIChatViewModel
    let userPreferencesService: UserPreferencesService
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                ChatInputBar(
                    text: $inputText,
                    isStreaming: viewModel.isStreaming,
                    onSend: {
                        viewModel.send(inputText)
                        inputText = ""
                    },
                    onStop: { viewModel.stop() }
                )
            }
            .background(STColors.background)
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .stNavigationBarStyle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
            }
        }
        .task {
            await viewModel.loadLatestConversation()
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageList: some View {
        if viewModel.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            messageView(message)
                                .id(message.id)
                        }

                        if let toolName = viewModel.activeToolName {
                            HStack {
                                ToolActivityChip(label: runningToolLabel(for: toolName), isRunning: true)
                                Spacer()
                            }
                            .id("active-tool")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        if message.kind == .draft, let draft = viewModel.decodeDraft(message) {
            DraftCardView(
                draft: draft,
                status: message.draftStatus ?? .pending,
                weightUnit: userPreferencesService.weightUnit,
                onSave: {
                    Task { await viewModel.saveDraft(messageID: message.id) }
                },
                onDiscard: {
                    viewModel.discardDraft(messageID: message.id)
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MessageBubbleView(
                    message: message,
                    isStreaming: viewModel.isStreaming && message.id == viewModel.messages.last?.id
                        && message.role == .assistant && message.kind == .text
                )
                if message.kind == .error {
                    Button("Retry") {
                        viewModel.retry()
                    }
                    .font(.stCaption)
                    .foregroundStyle(STColors.primary)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastID = viewModel.messages.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(STColors.primary)
            Text("Ask Grok about your training")
                .font(.stTitle)
                .foregroundStyle(STColors.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                examplePrompt("Summarize my last two weeks of training")
                examplePrompt("Create a legs template focused on quads")
                examplePrompt("Am I close to any PRs?")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func examplePrompt(_ text: String) -> some View {
        Button {
            inputText = text
        } label: {
            Text(text)
                .font(.stBody)
                .foregroundStyle(STColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(STColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
        .buttonStyle(.plain)
    }
}
#endif
