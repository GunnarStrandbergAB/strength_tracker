#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if !message.toolActivities.isEmpty {
                FlowingChips(activities: message.toolActivities)
            }

            if !message.text.isEmpty || isStreaming {
                HStack {
                    if message.role == .user { Spacer(minLength: 48) }
                    bubble
                    if message.role == .assistant { Spacer(minLength: 48) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubble: some View {
        markdownText
            .font(.system(size: 15))
            .foregroundStyle(message.kind == .error ? STColors.danger : STColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(message.kind == .error ? STColors.danger.opacity(0.4) : .clear, lineWidth: 1)
            )
    }

    private var bubbleBackground: Color {
        switch (message.role, message.kind) {
        case (.user, _): return STColors.primary.opacity(0.16)
        case (_, .error): return STColors.danger.opacity(0.08)
        default: return STColors.surface
        }
    }

    @ViewBuilder
    private var markdownText: some View {
        let display = isStreaming && !message.text.isEmpty ? message.text + " ●" : message.text
        if let attributed = try? AttributedString(
            markdown: display,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(display)
        }
    }
}

private struct FlowingChips: View {
    let activities: [ToolActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activities) { activity in
                ToolActivityChip(label: activity.label)
            }
        }
    }
}
#endif
