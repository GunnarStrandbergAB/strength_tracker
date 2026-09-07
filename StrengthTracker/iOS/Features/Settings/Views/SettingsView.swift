#if canImport(SwiftUI)
import SwiftUI
import StoreKit
import StrengthTrackerShared

struct SettingsView: View {
    @Environment(WeightRecordingService.self) private var weightRecordingService: WeightRecordingService?
    @State private var preferencesService: UserPreferencesService
    @State private var bodyWeightText: String = ""
    @Environment(BodyWeightProvider.self) private var bodyWeightProvider: BodyWeightProvider?
    @State private var healthSyncMessage: String?
    private var connectivityManager: ConnectivityManager?
    var proFeatureGate: ProFeatureGate? = nil
    var storeService: StoreService? = nil
    var aiCredentialsService: AICredentialsService? = nil
    var aiChatClient: (any AIChatClient)? = nil
    var aiMemoryService: AIMemoryService? = nil
    @State private var showUpgradeSheet = false
    @State private var connectionTestState: ConnectionTestState = .idle

    private enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    init(
        preferencesService: UserPreferencesService,
        connectivityManager: ConnectivityManager? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        storeService: StoreService? = nil,
        aiCredentialsService: AICredentialsService? = nil,
        aiChatClient: (any AIChatClient)? = nil,
        aiMemoryService: AIMemoryService? = nil
    ) {
        self.preferencesService = preferencesService
        self.connectivityManager = connectivityManager
        self.proFeatureGate = proFeatureGate
        self.storeService = storeService
        self.aiCredentialsService = aiCredentialsService
        self.aiChatClient = aiChatClient
        self.aiMemoryService = aiMemoryService
    }

    var body: some View {
        Form {
                // Subscription Section
                if let proFeatureGate, let storeService {
                    Section("Subscription") {
                        if proFeatureGate.hasProAccess && storeService.isProUser {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(STColors.primary)
                                Text("HellBentIron Pro")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(STColors.success)
                            }
                            Button("Manage Subscription") {
                                Task {
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                        try? await AppStore.showManageSubscriptions(in: windowScene)
                                    }
                                }
                            }
                        } else if proFeatureGate.hasProAccess && ProFeatureGate.isBeta {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(STColors.primary)
                                Text("HellBentIron Pro")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("Beta")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(STColors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(STColors.surface)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Button {
                                showUpgradeSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "crown")
                                        .foregroundStyle(STColors.primary)
                                    Text("Upgrade to Pro")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(STColors.textTertiary)
                                }
                            }
                        }

                        Button("Restore Purchases") {
                            Task {
                                await storeService.restorePurchases()
                            }
                        }
                        .foregroundStyle(STColors.textSecondary)
                    }
                }

                // Profile Section
                Section {
                    HStack {
                        Text("Body Weight")
                        Spacer()
                        TextField(
                            preferencesService.weightUnit == .kg ? "kg" : "lbs",
                            text: $bodyWeightText
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onChange(of: bodyWeightText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                let kg = preferencesService.weightUnit == .lbs ? value / 2.20462 : value
                                preferencesService.bodyWeightKg = kg
                            } else if newValue.isEmpty {
                                preferencesService.bodyWeightKg = nil
                            }
                        }
                        Text(preferencesService.weightUnit == .kg ? "kg" : "lbs")
                            .foregroundStyle(.secondary)
                    }
                    if let bodyWeightProvider {
                        Button {
                            Task {
                                do {
                                    try await bodyWeightProvider.requestHealthKitAccess()
                                    healthSyncMessage = bodyWeightProvider.source == .healthKit
                                        ? "Using Apple Health weight: \(preferencesService.weightUnit.format(bodyWeightProvider.current, decimals: 1))"
                                        : "No weight sample in Apple Health yet."
                                } catch {
                                    healthSyncMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Sync with Apple Health", systemImage: "heart.text.square")
                        }
                        if let healthSyncMessage {
                            Text(healthSyncMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text(bodyWeightProvider?.source == .healthKit
                        ? "Apple Health weight is in use for bodyweight exercises and calorie estimation."
                        : "Used for bodyweight exercises and calorie estimation. Syncs from Apple Health when available.")
                }

                if let weightRecordingService {
                    Section {
                        NavigationLink("Weight logging") {
                            WeightRecordingSettingsView(service: weightRecordingService, bodyWeightKg: bodyWeightProvider?.current ?? UserPreferencesService.defaultBodyWeightKg,
                                                        unit: preferencesService.weightUnit)
                        }
                    } footer: { Text("Set per-dumbbell or combined weight, explain per-side reps, and review historical volume.") }
                }
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
                Section {
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

                    Picker("Intensity Metric", selection: $preferencesService.intensityMetric) {
                        Text("RPE").tag(IntensityMetric.rpe)
                        Text("RIR").tag(IntensityMetric.rir)
                    }

                    Toggle("Always Show Intensity", isOn: $preferencesService.alwaysShowRPE)

                    Stepper(
                        value: $preferencesService.defaultReps,
                        in: 1...30,
                        step: 1
                    ) {
                        HStack {
                            Text("Default Reps")
                            Spacer()
                            Text("\(preferencesService.defaultReps)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Workout")
                } footer: {
                    Text("RPE = Rate of Perceived Exertion (1–10). RIR = Reps In Reserve (0–9). Existing logs convert automatically.")
                }

                // Deload Section
                Section {
                    Stepper(
                        value: $preferencesService.deloadWeightPercentage,
                        in: 10...80,
                        step: 5
                    ) {
                        HStack {
                            Text("Deload Weight")
                            Spacer()
                            Text("\(preferencesService.deloadWeightPercentage)%")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(
                        value: $preferencesService.deloadRestPercentage,
                        in: 25...100,
                        step: 5
                    ) {
                        HStack {
                            Text("Deload Rest Timer")
                            Spacer()
                            Text("\(preferencesService.deloadRestPercentage)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Deload")
                } footer: {
                    Text("Percentage of normal weight and rest time used when a workout is marked as deload.")
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

                // Webhook Section
                Section {
                    TextField("https://example.com/webhook", text: $preferencesService.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer token (optional)", text: $preferencesService.webhookBearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Webhook")
                } footer: {
                    Text("Posts workout JSON to this URL after every completed workout. Use with AI trainers, n8n, Zapier, or any HTTP endpoint.")
                }

                // AI Assistant Section
                if let aiCredentialsService {
                    aiAssistantSection(credentials: aiCredentialsService)
                }

                // Legal Section
                Section("Legal") {
                    Link(destination: URL(string: "https://hellbentiron.com/privacy")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 12))
                                .foregroundStyle(STColors.textTertiary)
                        }
                    }

                    Link(destination: URL(string: "https://hellbentiron.com/terms")!) {
                        HStack {
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 12))
                                .foregroundStyle(STColors.textTertiary)
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
            .navigationBarTitleDisplayMode(.inline)
            .stNavigationBarStyle()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                if let storeService {
                    ProUpgradeView(storeService: storeService)
                }
            }
            .onAppear { updateBodyWeightText() }
            .onChange(of: preferencesService.defaultRestSeconds) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.weightUnit) { _, _ in
                syncSettingsToWatch()
                updateBodyWeightText()
            }
            .onChange(of: preferencesService.autoStartRestTimer) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.defaultReps) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.distanceUnit) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.alwaysShowRPE) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.intensityMetric) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.deloadWeightPercentage) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.deloadRestPercentage) { _, _ in syncSettingsToWatch() }
            .onChange(of: preferencesService.bodyWeightKg) { _, _ in syncSettingsToWatch() }
    }

    @ViewBuilder
    private func aiAssistantSection(credentials: AICredentialsService) -> some View {
        @Bindable var credentials = credentials
        Section {
            Toggle("AI Assistant", isOn: $preferencesService.aiChatEnabled)

            SecureField("xAI API key", text: $credentials.xaiAPIKey)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: credentials.xaiAPIKey) { _, _ in
                    connectionTestState = .idle
                }

            if let aiChatClient {
                Button {
                    connectionTestState = .testing
                    let client = aiChatClient
                    Task {
                        do {
                            try await client.validateKey()
                            connectionTestState = .success
                        } catch let error as AIClientError {
                            connectionTestState = .failure(error.userMessage)
                        } catch {
                            connectionTestState = .failure(error.localizedDescription)
                        }
                    }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch connectionTestState {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(STColors.success)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(STColors.danger)
                        }
                    }
                }
                .disabled(!credentials.hasKey || connectionTestState == .testing)

                if case .failure(let message) = connectionTestState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(STColors.danger)
                }
            }

            if let aiMemoryService {
                NavigationLink {
                    AIMemoriesView(memoryService: aiMemoryService)
                } label: {
                    HStack {
                        Text("Memories")
                        Spacer()
                        Text("\(aiMemoryService.memories.count)")
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Chat with Grok about your training. Your key is stored in the device keychain and sent only to api.x.ai.")
        }
    }

    private func updateBodyWeightText() {
        guard let kg = preferencesService.bodyWeightKg else {
            bodyWeightText = ""
            return
        }
        let displayValue = preferencesService.weightUnit == .lbs ? kg * 2.20462 : kg
        bodyWeightText = String(format: "%.1f", displayValue)
    }

    private func syncSettingsToWatch() {
        connectivityManager?.syncSettings([
            "defaultRestSeconds": preferencesService.defaultRestSeconds,
            "defaultReps": preferencesService.defaultReps,
            "weightUnit": preferencesService.weightUnit.rawValue,
            "autoStartRestTimer": preferencesService.autoStartRestTimer,
            "distanceUnit": preferencesService.distanceUnit.rawValue,
            "intensityMetric": preferencesService.intensityMetric.rawValue,
            "bodyWeightKg": preferencesService.bodyWeightKg ?? 0
        ])
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


struct WeightRecordingSettingsView: View {
    let service: WeightRecordingService
    let bodyWeightKg: Double
    let unit: WeightUnit
    @State private var catalog: [Exercise] = []
    @State private var selections: Set<UUID> = []
    @State private var configurations: [UUID: WeightRecording] = [:]
    @State private var search = ""
    @State private var includeHistory = false
    @State private var updateFuture = true
    @State private var start = Date(timeIntervalSince1970: 0)
    @State private var end = Date()
    @State private var preview: WeightRecordingService.Preview?
    @State private var message: String?
    @State private var showUndo = false
    @State private var working = false
    var body: some View {
        Form {
            Section {
                Text("Keep logging the weight of one dumbbell. Tell the app how many dumbbells and sides each row covers so it can calculate total volume.")
                Text("Unconfirmed history keeps its original calculation until you review it. Entered weights and reps are preserved.").font(.caption)
                Button("Select all as weight per dumbbell") { selectAll(.perDumbbell) }
                Button("Select all as combined weight") { selectAll(.combined) }
                Button("Clear selection / leave unresolved") { selections.removeAll() }
            }
            Section("Exercise exceptions") {
                TextField("Find an exercise", text: $search)
                ForEach(catalog.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { exercise in
                    DisclosureGroup {
                        Toggle("Include in this update", isOn: Binding(get: { selections.contains(exercise.id) }, set: {
                            if $0 { selections.insert(exercise.id) } else { selections.remove(exercise.id) }
                        }))
                        WeightRecordingFields(value: Binding(get: { configurations[exercise.id] ?? WeightRecording() }, set: {
                            configurations[exercise.id] = $0; selections.insert(exercise.id)
                        }))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                            Text(selections.contains(exercise.id) ? "Selected" : "Unchanged").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Apply to") {
                Toggle("Future exercise defaults", isOn: $updateFuture)
                Text("Unconfirmed template and plan targets receive this interpretation. Targets with a known convention keep it. An active workout keeps its current convention.").font(.caption)
                Toggle("Correct completed workout history", isOn: $includeHistory)
                if includeHistory {
                    DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                    DatePicker("Through", selection: $end, in: start...Date(), displayedComponents: .date)
                }
            }
            if let preview {
                Section("Review correction") {
                    Text("\(preview.workoutCount) completed workouts · \(preview.changes.count) recording settings")
                    Text("Affected workout volume: \(unit.format(preview.beforeVolume, decimals: 0)) × reps → \(unit.format(preview.afterVolume, decimals: 0)) × reps")
                    Text("Weights, reps, dates and workout IDs stay the same. Analytics and volume records will be recalculated.").font(.caption)
                    Button("Apply reviewed correction") { run { try await service.apply(preview); self.preview = nil; message = "Weight logging updated."; await load() } }.disabled(preview.changes.isEmpty)
                    Button("Cancel preview", role: .cancel) { self.preview = nil }
                }
            } else {
                Button("Preview changes") { run {
                    let interval = includeHistory ? DateInterval(start: Calendar.current.startOfDay(for: start), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!) : nil
                    preview = try await service.preview(selections: configurations.filter { selections.contains($0.key) }, history: interval, updateFuture: updateFuture, bodyWeightKg: bodyWeightKg)
                }}.disabled(selections.isEmpty || (!includeHistory && !updateFuture))
            }
            if let message { Text(message).font(.callout) }
            if let error = service.errorMessage {
                Text(error).foregroundStyle(.red)
                Button("Retry interrupted correction") { run { await service.resume() } }
            }
            if service.canUndo { Button("Undo last correction") { showUndo = true } }
        }
        .disabled(working || service.isBusy)
        .overlay { if working || service.isBusy { ProgressView("Updating weight logging…") } }
        .navigationTitle("Weight logging")
        .task { await load() }
        .onChange(of: selections) { _, _ in preview = nil }
        .onChange(of: configurations) { _, _ in preview = nil }
        .onChange(of: includeHistory) { _, _ in preview = nil }
        .onChange(of: updateFuture) { _, _ in preview = nil }
        .onChange(of: start) { _, _ in preview = nil }
        .onChange(of: end) { _, _ in preview = nil }
        .alert("Undo the last weight-logging correction?", isPresented: $showUndo) {
            Button("Undo correction") { run { try await service.undo(); preview = nil; message = "Previous recording settings restored."; await load() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Restores the previous conventions and recalculates analytics. Your entered weights and reps are preserved.") }
    }
    private func selectAll(_ entry: WeightRecording.WeightEntry) {
        for exercise in catalog {
            var config = configurations[exercise.id] ?? WeightRecording()
            config.weightEntry = entry; configurations[exercise.id] = config
        }
        selections = Set(catalog.map(\.id))
    }
    private func load() async {
        do {
            catalog = try await service.catalog()
            configurations = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.weightRecording ?? DumbbellDefaults.recording(for: $0.name) ?? WeightRecording()) })
        } catch { message = error.localizedDescription }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        working = true; message = nil
        Task { do { try await action() } catch { message = error.localizedDescription }; working = false }
    }
}
#endif
