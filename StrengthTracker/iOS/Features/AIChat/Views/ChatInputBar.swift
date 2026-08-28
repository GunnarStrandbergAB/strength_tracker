#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your training…", text: $text, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(STColors.textPrimary)
                .lineLimit(1...5)
                .focused($isFocused)
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
                    .frame(width: 38, height: 38)
                    .background(canSend || isStreaming ? STColors.primary : STColors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(STColors.background)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
#endif
