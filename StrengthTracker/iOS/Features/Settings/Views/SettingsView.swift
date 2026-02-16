#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SettingsView: View {
    @State private var preferencesService: UserPreferencesService

    init(preferencesService: UserPreferencesService) {
        self.preferencesService = preferencesService
    }

    var body: some View {
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
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Auto-start Rest Timer", isOn: $preferencesService.autoStartRestTimer)
                }

                // Data Management Section
                Section("Data") {
                    Button("Reset All Preferences") {
                        preferencesService.resetToDefaults()
                    }
                    .foregroundStyle(.orange)

                    if preferencesService.hasSeededExercises {
                        HStack {
                            Text("Exercise Library")
                            Spacer()
                            Text("Loaded")
                                .font(.caption)
                                .foregroundStyle(STColors.success)
                        }
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Credits Section
                Section("Credits") {
                    Text("Built with SwiftUI and SwiftData")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Icons by SF Symbols")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .stNavigationBarStyle()
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
    NavigationStack {
        SettingsView(preferencesService: UserPreferencesService())
    }
}

#endif
