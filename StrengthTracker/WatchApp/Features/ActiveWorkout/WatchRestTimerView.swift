import SwiftUI
import StrengthTrackerShared
#if os(watchOS)
import WatchKit
#endif

struct WatchRestTimerView: View {
    @State private var viewModel: WatchWorkoutViewModel

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Circular progress ring with timer
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 100, height: 100)

                // Progress ring
                Circle()
                    .trim(from: 0, to: viewModel.restProgress)
                    .stroke(
                        primaryYellow,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: viewModel.restProgress)

                // Timer text
                VStack(spacing: 2) {
                    Text("REST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .tracking(2)

                    Text(viewModel.restTimerText)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            // Skip button
            Button {
                #if os(watchOS)
                WKInterfaceDevice.current().play(.click)
                #endif
                viewModel.skipRestTimer()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                    Text("SKIP")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding()
        // Haptic feedback on timer completion is handled by WatchWorkoutViewModel.restTimerCompleted()
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text("rest=\(viewModel.isResting ? "Y" : "N") rem=\(String(format: "%.1f", viewModel.restTimeRemaining)) dur=\(String(format: "%.1f", viewModel.restDuration))\nprog=\(String(format: "%.2f", viewModel.restProgress)) text=\(viewModel.restTimerText)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(2)
                .background(.black.opacity(0.3))
                .cornerRadius(4)
        }
        #endif
    }
}
