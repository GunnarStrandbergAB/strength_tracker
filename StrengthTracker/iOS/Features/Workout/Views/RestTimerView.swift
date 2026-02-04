#if canImport(SwiftUI)
import SwiftUI

struct RestTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service: RestTimerService

    init(service: RestTimerService) {
        self.service = service
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 32) {
                // Circular progress with countdown
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 12)
                        .frame(width: 240, height: 240)

                    // Progress circle
                    Circle()
                        .trim(from: 0, to: service.progress)
                        .stroke(
                            service.isCompleted ? Color.green : Color.blue,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: service.progress)

                    // Countdown text
                    VStack(spacing: 8) {
                        Text(service.formattedTime)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        if service.isCompleted {
                            Text("Rest Complete!")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if service.isRunning {
                            Text("Resting...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Paused")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()

                // Control buttons
                HStack(spacing: 24) {
                    if service.isRunning {
                        Button {
                            service.stop()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(width: 100)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        Button {
                            service.start()
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .frame(width: 100)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    Button {
                        service.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.clockwise")
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                }
                .padding(.horizontal)

                // Quick add time buttons
                if service.isRunning {
                    HStack(spacing: 16) {
                        QuickTimeButton(seconds: 30, service: service)
                        QuickTimeButton(seconds: 60, service: service)
                        QuickTimeButton(seconds: 90, service: service)
                    }
                    .padding(.horizontal)
                }

                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal, 32)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
            )
            .padding(24)
        }
        .onChange(of: service.isCompleted) { _, isCompleted in
            if isCompleted {
                triggerCompletionHaptic()
            }
        }
    }

    private func triggerCompletionHaptic() {
        #if canImport(UIKit)
        import UIKit
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}

private struct QuickTimeButton: View {
    let seconds: Int
    let service: RestTimerService

    var body: some View {
        Button {
            service.remainingSeconds += seconds
            service.totalSeconds += seconds
        } label: {
            Text("+\(seconds)s")
                .font(.caption)
                .frame(width: 60)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
    }
}

#Preview {
    @Previewable @State var service = RestTimerService()

    RestTimerView(service: service)
        .onAppear {
            service.start(seconds: 120)
        }
}

#endif
