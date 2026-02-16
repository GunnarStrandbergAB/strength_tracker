#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SettingsView: View {
    @State private var preferencesService: UserPreferencesService

    init(preferencesService: UserPreferencesService) {
        self.preferencesService = preferencesService
    }

    var body: some View {
        NavigationStack {
            Form {
                // Units Section
                Section("Units") {
                    Picker("Weight Unit", selection: $preferencesService.weightUnit) {
                        Text("Kilograms (kg)").tag(WeightUnit.kg)
                        Text("Pounds (lbs)").tag(WeightUnit.lbs)
                    }

                    Picker("Distance Unit", selection: $preferencesService.distanceUnit) {
                        Text("Kilometers (km)").tag(DistanceUnit.km)
                        Text("Miles").tag(DistanceUnit.miles)
                    }
                }

                // Workout Settings Section
                Section("Workout") {
                    Stepper(
                        value: $preferencesService.defaultRestSeconds,
                        in: 30...300,
                        step: 15
                    ) {
                        HStack {
                            Text("Default Rest Timer")
                            Spacer()
                            Text("\(formatSeconds(preferencesService.defaultRestSeconds))")
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Auto-start Rest Timer", isOn: $preferencesService.autoStartRestTimer)
                }

                // Data Management Section
                Section("Data") {
                    Button("Reset All Preferences") {
                        preferencesService.resetToDefaults()
                    }
                    .foregroundColor(.orange)

                    if preferencesService.hasSeededExercises {
                        HStack {
                            Text("Exercise Library")
                            Spacer()
                            Text("Loaded")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Credits Section
                Section("Credits") {
                    Text("Built with SwiftUI and SwiftData")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Icons by SF Symbols")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 && remainingSeconds > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(remainingSeconds)s"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

#Preview {
    SettingsView(preferencesService: UserPreferencesService())
}

#endif
