#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    @FocusState.Binding var isFocused: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    private var maximumLines: Int {
        verticalSizeClass == .compact ? 2 : (typeSize.isAccessibilitySize ? 3 : 5)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $text,
                prompt: Text("Ask about your training…").foregroundStyle(STColors.textSecondary), axis: .vertical)
                .font(.body)
                .foregroundStyle(STColors.textPrimary)
                .tint(STColors.primary)
                .lineLimit(1...maximumLines)
                .focused($isFocused)
                .accessibilityLabel("Message to AI assistant")
                .accessibilityIdentifier("chat-message-input")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(STColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(STColors.border, lineWidth: 1)
                )

            Button {
                if isStreaming {
                    onStop()
                } else {
                    onSend()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSend || isStreaming ? .black : STColors.textTertiary)
                    .frame(width: 44, height: 44)
                    .background(canSend || isStreaming ? STColors.primary : STColors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !isStreaming)
            .accessibilityLabel(isStreaming ? "Stop response" : "Send message")
            .accessibilityIdentifier("chat-send-or-stop")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(STColors.background)
        .overlay(alignment: .top) { STColors.border.frame(height: 1) }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
#endif
