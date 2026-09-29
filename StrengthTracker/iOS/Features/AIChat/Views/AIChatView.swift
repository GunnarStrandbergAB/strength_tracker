#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct AIChatView: View {
    let viewModel: AIChatViewModel
    let userPreferencesService: UserPreferencesService
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var messageViewport = CGSize.zero
    @State private var scrollState = ChatScrollFollowState()
    @State private var scrollRequest = 0
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
                        scrollState.requestLatest()
                        scrollRequest += 1
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
                        scrollState = ChatScrollFollowState()
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
                            ChatMessageRow(message: message,
                                weightUnit: userPreferencesService.weightUnit,
                                isStreaming: viewModel.isStreaming && message.id == viewModel.messages.last?.id && message.role == .assistant && message.kind == .text,
                                isSaving: viewModel.savingDraftID == message.id,
                                onSave: { Task { await viewModel.saveDraft(messageID: message.id) } },
                                onDiscard: { viewModel.discardDraft(messageID: message.id) },
                                onRetry: { viewModel.retry() })
                                .equatable()
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
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("chat-scroll")).maxY } action: { bottom in
                                if #available(iOS 18.0, *) {} else {
                                    scrollState.updateDistance(bottom - messageViewport.height)
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .coordinateSpace(name: "chat-scroll")
            .modifier(ChatScrollTracking(state: $scrollState))
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat-messages")
            .onGeometryChange(for: CGSize.self) { geometry in
                CGSize(width: geometry.size.width,
                       height: max(0, geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom))
            } action: {
                messageViewport = $0
                if scrollState.shouldFollow { scrollRequest += 1 }
            }
            .task(id: scrollRequest) {
                // Let the scroll view apply its new insets before revealing the tail.
                // This also handles rotation and the composer growing while typing.
                await Task.yield()
                guard !Task.isCancelled, scrollState.shouldFollow else { return }
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: viewModel.messages.last) { _, _ in
                if scrollState.contentChanged() { scrollRequest += 1 }
            }
            .onChange(of: viewModel.activeToolName) { _, _ in
                if scrollState.shouldFollow { scrollRequest += 1 }
            }
            .onChange(of: scrollState.shouldFollow) { _, follows in
                if follows { scrollRequest += 1 }
            }
            .overlay(alignment: .bottomTrailing) {
                if !scrollState.followsLatest && !viewModel.messages.isEmpty {
                    Button {
                        scrollState.requestLatest()
                        scrollRequest += 1
                    } label: {
                        Label(scrollState.hasUnreadMessages ? "New messages" : "Latest", systemImage: "arrow.down")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(STColors.background).background(STColors.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to latest message")
                    .accessibilityIdentifier("chat-jump-to-latest")
                    .padding(12)
                }
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

/// Follow new content only when the reader has not scrolled away. Geometry
/// changes alone must not mistake a growing reply for an intentional scroll.
struct ChatScrollFollowState: Equatable {
    private(set) var followsLatest = true
    private(set) var isInteracting = false
    private(set) var isNearBottom = true
    private(set) var hasUnreadMessages = false
    private var followWhenIdle = false
    var shouldFollow: Bool { followsLatest && !isInteracting }

    mutating func updateDistance(_ distance: CGFloat) {
        isNearBottom = distance <= 80
    }
    mutating func beginInteraction() { isInteracting = true; followsLatest = false }
    mutating func endInteraction() {
        isInteracting = false
        followsLatest = followWhenIdle || isNearBottom
        followWhenIdle = false
        if followsLatest { hasUnreadMessages = false }
    }
    mutating func contentChanged() -> Bool {
        if !shouldFollow { hasUnreadMessages = true }
        return shouldFollow
    }
    mutating func requestLatest() {
        followsLatest = true
        followWhenIdle = isInteracting
        hasUnreadMessages = false
    }
}

private struct ChatScrollTracking: ViewModifier {
    @Binding var state: ChatScrollFollowState
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(state.shouldFollow ? .bottom : nil, for: .sizeChanges)
                .defaultScrollAnchor(.top, for: .alignment)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height <= 80
                } action: { _, nearBottom in
                    state.updateDistance(nearBottom ? 0 : 81)
                }
                .onScrollPhaseChange { _, phase, context in
                    switch phase {
                    case .tracking, .interacting, .decelerating: state.beginInteraction()
                    case .idle where state.isInteracting:
                        let geometry = context.geometry
                        state.updateDistance(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height)
                        state.endInteraction()
                    default: break
                    }
                }
        } else {
            content.defaultScrollAnchor(state.shouldFollow ? .bottom : nil)
                .simultaneousGesture(DragGesture(minimumDistance: 4)
                .onChanged { _ in state.beginInteraction() }
                .onEnded { value in
                    // iOS 17 has no scroll-phase callback. A fling can coast in
                    // either direction after this gesture ends; keep it detached
                    // until Latest is tapped or a later drag ends at the bottom.
                    if abs(value.predictedEndTranslation.height - value.translation.height) > 10 {
                        state.updateDistance(81)
                    }
                    state.endInteraction()
                })
        }
    }
}

/// Unchanged rows avoid decoding large plan proposals and parsing Markdown
/// whenever another message streams, the keyboard moves, or the user types.
private struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let weightUnit: WeightUnit
    let isStreaming: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onRetry: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.weightUnit == rhs.weightUnit && lhs.isStreaming == rhs.isStreaming && lhs.isSaving == rhs.isSaving
    }

    var body: some View {
        if message.kind == .receipt, let receipt: AIReceipt = decoded(message.receiptJSON) {
            ReceiptCardView(receipt: receipt)
        } else if message.kind == .draft, let draft: AIDraft = decoded(message.draftJSON) {
            DraftCardView(draft: draft, status: message.draftStatus ?? .pending, weightUnit: weightUnit,
                isSaving: isSaving, onSave: onSave, onDiscard: onDiscard)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MessageBubbleView(message: message, isStreaming: isStreaming)
                if message.kind == .error {
                    Button("Retry", action: onRetry).font(.stCaption).foregroundStyle(STColors.primary)
                }
            }
        }
    }

    private func decoded<T: Decodable>(_ json: String?) -> T? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
#endif
