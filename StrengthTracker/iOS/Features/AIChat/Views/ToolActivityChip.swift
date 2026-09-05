#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Small capsule showing a tool invocation ("Read 12 workouts").
struct ToolActivityChip: View {
    let label: String
    var isRunning: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .tint(STColors.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.success)
            }
            Text(label)
                .font(.stCaption)
                .foregroundStyle(STColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(STColors.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(STColors.border, lineWidth: 1))
    }
}

/// Human-readable label while a tool is running.
func runningToolLabel(for name: String) -> String {
    switch name {
    case "list_exercises": return "Browsing exercises…"
    case "get_training_history": return "Reading training history…"
    case "get_analytics_insights": return "Analyzing your training…"
    case "get_personal_records": return "Checking personal records…"
    case "get_active_plan": return "Checking your plan…"
    case "list_templates": return "Browsing templates…"
    case "save_memory": return "Saving a memory…"
    case "forget_memory": return "Forgetting…"
    case "propose_exercise": return "Drafting an exercise…"
    case "propose_template": return "Drafting a template…"
    case "propose_training_plan": return "Drafting a plan…"
    case "get_workout": return "Reading workout…"
    case "log_set": return "Logging set…"
    case "add_sets": return "Adding sets…"
    case "remove_set": return "Removing set…"
    case "add_exercise": return "Adding exercise…"
    case "remove_exercise": return "Removing exercise…"
    case "change_exercise": return "Swapping exercise…"
    case "set_notes": return "Saving note…"
    case "set_deload": return "Updating workout…"
    case "start_workout": return "Starting workout…"
    case "finish_workout": return "Finishing workout…"
    case "cancel_workout": return "Preparing to cancel…"
    default: return "Working…"
    }
}
#endif
