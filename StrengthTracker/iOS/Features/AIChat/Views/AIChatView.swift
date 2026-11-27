#if canImport(SwiftUI)
import SwiftUI
import Observation
import StrengthTrackerShared

/// The transcript fills the screen and the composer sits under it. Two rules keep
/// this screen stable, and both are about never letting layout drive layout:
///
/// - Keyboard: `ChatKeyboardAvoidance` lifts the transcript and composer by the frame
///   UIKit posts with its keyboard notifications. SwiftUI's automatic avoidance is
///   switched off here because the keyboard position it follows can be stale.
/// - Scrolling: the transcript is a plain stack in a bottom-anchored scroll view, so
///   SwiftUI itself keeps the newest message in view. The only programmatic scrolls
///   are the two explicit ones: the user sends a message, or taps "Latest".
struct AIChatView: View {
    let viewModel: AIChatViewModel
    let userPreferencesService: UserPreferencesService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var inputText = ""
    @State private var scroll = ChatScrollState()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatTranscript(viewModel: viewModel, weightUnit: userPreferencesService.weightUnit, scroll: scroll) { prompt in
                    inputText = prompt
                    isInputFocused = true
                }
                ChatInputBar(
                    text: $inputText,
                    isStreaming: viewModel.isStreaming,
                    isFocused: $isInputFocused,
                    onSend: send,
                    onStop: { viewModel.stop() }
                )
            }
            .modifier(ChatKeyboardAvoidance())
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
                    .accessibilityIdentifier("chat-close")
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { isInputFocused = false }
        }
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

    private func send() {
        guard !viewModel.isStreaming,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.send(inputText)
        inputText = ""
    }
}

// MARK: - Scroll state

/// Whether the reader is at the newest message. Written from scroll geometry and read
/// only by the "Latest" button, so a change never re-lays-out the transcript.
@MainActor @Observable
final class ChatScrollState {
    /// Closer to the end than this still counts as reading the newest message.
    nonisolated static let nearBottomDistance: CGFloat = 80

    private(set) var isNearBottom = true
    private(set) var hasUnreadMessages = false
    /// Bumped to ask the transcript to show the newest message.
    private(set) var jumpRequests = 0

    func setNearBottom(_ nearBottom: Bool) {
        guard nearBottom != isNearBottom else { return }
        isNearBottom = nearBottom
        if nearBottom { hasUnreadMessages = false }
    }

    /// Something arrived or grew at the end of the transcript.
    func contentChanged() {
        if !isNearBottom { hasUnreadMessages = true }
    }

    func jumpToLatest() {
        hasUnreadMessages = false
        jumpRequests += 1
    }
}

// MARK: - Transcript

private struct ChatTranscript: View {
    let viewModel: AIChatViewModel
    let weightUnit: WeightUnit
    let scroll: ChatScrollState
    let onExamplePrompt: (String) -> Void
    private static let bottomID = "chat-bottom"

    var body: some View {
        Group {
            if viewModel.messages.isEmpty {
                // Scrollable so the prompts stay reachable in the space a keyboard leaves.
                ScrollView { ChatWelcome(onPrompt: onExamplePrompt) }
                    .accessibilityIdentifier("chat-messages")
            } else {
                // A separate scroll view from the welcome screen: a loaded or newly
                // started conversation always opens at its newest message.
                messages
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var messages: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy on purpose. Replies and plan cards differ in height by
                    // an order of magnitude; a lazy stack has to estimate the rows it
                    // has not built, and those estimates shifting under a
                    // bottom-anchored scroll view is what made scrolling jump and hang.
                    VStack(spacing: 0) {
                        VStack(spacing: 14) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageRow(message: message,
                                    weightUnit: weightUnit,
                                    isStreaming: viewModel.isStreaming && message.id == viewModel.messages.last?.id && message.role == .assistant && message.kind == .text,
                                    isSaving: viewModel.savingDraftID == message.id,
                                    onSave: { Task { await viewModel.saveDraft(messageID: message.id) } },
                                    onDiscard: { viewModel.discardDraft(messageID: message.id) },
                                    onRetry: { viewModel.retry() })
                                    .equatable()
                            }

                            if let toolName = viewModel.activeToolName {
                                HStack {
                                    ToolActivityChip(label: runningToolLabel(for: toolName), isRunning: true)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        // The bottom spacing is the scroll target, so "latest" is the very
                        // end of the content. Stopping short of it would stop the follow.
                        Color.clear.frame(height: 12).id(Self.bottomID)
                    }
                    // A short conversation starts under the title, not against the composer.
                    .frame(minHeight: viewport.size.height, alignment: .top)
                    .onGeometryChange(for: Bool.self) { content in
                        guard let visible = content.bounds(of: .scrollView) else { return true }
                        return content.size.height - visible.maxY <= ChatScrollState.nearBottomDistance
                    } action: { nearBottom in
                        scroll.setNearBottom(nearBottom)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .accessibilityIdentifier("chat-messages")
                .onChange(of: viewModel.messages.last) { previous, latest in
                    if let latest, latest.role == .user, latest.id != previous?.id {
                        // The user just sent this; show it wherever they were reading.
                        scroll.jumpToLatest()
                    } else {
                        scroll.contentChanged()
                    }
                }
                .onChange(of: scroll.jumpRequests) { _, _ in
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
                .overlay(alignment: .bottomTrailing) {
                    ChatLatestButton(scroll: scroll)
                }
            }
        }
    }
}

private struct ChatLatestButton: View {
    let scroll: ChatScrollState

    var body: some View {
        if !scroll.isNearBottom {
            Button {
                scroll.jumpToLatest()
            } label: {
                Label(scroll.hasUnreadMessages ? "New messages" : "Latest", systemImage: "arrow.down")
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

private struct ChatWelcome: View {
    let onPrompt: (String) -> Void

    var body: some View {
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
            onPrompt(text)
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

// MARK: - Keyboard

/// Pads the content above the docked keyboard.
///
/// The padding comes from the end frame in UIKit's keyboard notifications, not from
/// SwiftUI's keyboard safe area. After a field with an accessory bar has been used
/// (the workout number pad, any "Done" toolbar), the system's own keyboard tracking
/// can place the next keyboard lower than it really is until the keyboard changes
/// again, which left the composer hidden behind it. The notification frames stay correct.
private struct ChatKeyboardAvoidance: ViewModifier {
    @State private var keyboardOverlap: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardOverlap)
            // Measured on the padded container, whose frame does not depend on the padding.
            .background {
                KeyboardOverlapReader { overlap, duration in
                    guard overlap != keyboardOverlap else { return }
                    withAnimation(.easeOut(duration: duration)) { keyboardOverlap = overlap }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct KeyboardOverlapReader: UIViewRepresentable {
    let onChange: (_ overlap: CGFloat, _ duration: TimeInterval) -> Void

    func makeUIView(context: Context) -> KeyboardOverlapView {
        let view = KeyboardOverlapView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: KeyboardOverlapView, context: Context) {
        view.onChange = onChange
    }
}

/// Reports how far the docked keyboard reaches into this view, measured from its bottom edge.
private final class KeyboardOverlapView: UIView {
    var onChange: ((_ overlap: CGFloat, _ duration: TimeInterval) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // Show and hide describe the docked keyboard only: UIKit posts "show" again
        // whenever its height changes, and "hide" when it undocks or floats.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let window, let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screen = (notification.object as? UIScreen) ?? window.screen
        let top = convert(end, from: screen.coordinateSpace).minY
        report(max(0, bounds.maxY - top), notification)
    }

    /// The end frame of a hiding keyboard is deliberately not read: it can describe an
    /// accessory bar the keyboard leaves behind. Nothing of a hidden keyboard needs avoiding.
    @objc private func keyboardWillHide(_ notification: Notification) {
        report(0, notification)
    }

    private func report(_ overlap: CGFloat, _ notification: Notification) {
        // Some systems post a zero duration for a keyboard that still slides away.
        let posted = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
        onChange?(overlap, posted > 0 ? posted : 0.25)
    }
}
#endif
