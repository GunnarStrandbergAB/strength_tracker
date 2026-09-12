#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct AIChatView: View {
    let viewModel: AIChatViewModel
    let userPreferencesService: UserPreferencesService
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var messageViewport = CGSize.zero
    @FocusState private var isInputFocused: Bool
    private let bottomID = "chat-bottom"

    var body: some View {
        NavigationStack {
            messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(
                    text: $inputText,
                    isStreaming: viewModel.isStreaming,
                    isFocused: $isInputFocused,
                    onSend: {
                        guard !viewModel.isStreaming,
                              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
                        isInputFocused = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .accessibilityLabel("Close AI assistant")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isInputFocused {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundStyle(STColors.textSecondary)
                        }
                        .accessibilityLabel("Hide keyboard")
                        .accessibilityIdentifier("chat-hide-keyboard")
                    }
                    Button {
                        viewModel.startNewConversation()
                        inputText = ""
                        isInputFocused = false
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .disabled(viewModel.messages.isEmpty)
                    .accessibilityLabel("New conversation")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { isInputFocused = false }
        .task {
            await viewModel.loadLatestConversation()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            // The welcome content must be able to shrink/scroll just like a conversation.
            // Otherwise its minimum height can push the composer below a docked keyboard.
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
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
                        }

                        // Include the bottom spacing in the scroll target itself.
                        Color.clear.frame(height: 1).padding(.bottom, 12).id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .defaultScrollAnchor(viewModel.messages.isEmpty ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat-messages")
            .onGeometryChange(for: CGSize.self) { geometry in
                CGSize(width: geometry.size.width,
                       height: max(0, geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom))
            } action: { messageViewport = $0 }
            .task(id: messageViewport) {
                // Let the scroll view apply its new insets before revealing the tail.
                // This also handles rotation and the composer growing while typing.
                await Task.yield()
                guard !Task.isCancelled else { return }
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.last) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.activeToolName) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        if message.kind == .receipt, let receipt = viewModel.decodeReceipt(message) {
            ReceiptCardView(receipt: receipt)
        } else if message.kind == .draft, let draft = viewModel.decodeDraft(message) {
            DraftCardView(
                draft: draft,
                status: message.draftStatus ?? .pending,
                weightUnit: userPreferencesService.weightUnit,
                isSaving: viewModel.savingDraftID == message.id,
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

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if !viewModel.messages.isEmpty {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(STColors.primary)
            Text("Ask Grok about your training")
                .font(.headline)
                .foregroundStyle(STColors.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                examplePrompt("Summarize my last two weeks of training")
                examplePrompt("Create a legs template focused on quads")
                examplePrompt("Am I close to any PRs?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }

    private func examplePrompt(_ text: String) -> some View {
        Button {
            inputText = text
            isInputFocused = true
        } label: {
            Text(text)
                .font(.subheadline)
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
