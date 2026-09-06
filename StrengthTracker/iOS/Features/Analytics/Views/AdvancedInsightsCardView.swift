import SwiftUI
import StrengthTrackerShared

struct AdvancedInsightsCardView: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        NavigationLink { AdvancedInsightsView(viewModel: viewModel) } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Explore training patterns").font(.headline).foregroundStyle(STColors.textPrimary)
                    Text("Your routine and how it changes").font(.subheadline).foregroundStyle(STColors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(STColors.primary)
            }.padding(18).background(STColors.surface).clipShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}
