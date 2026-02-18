import Foundation
import Observation

@Observable
public final class WebhookService: @unchecked Sendable {
    private let preferencesService: UserPreferencesService
    private let session: URLSession

    @MainActor
    public init(preferencesService: UserPreferencesService) {
        self.preferencesService = preferencesService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    @MainActor
    public func send(_ workout: Workout) async {
        let urlString = preferencesService.webhookURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = preferencesService.webhookBearerToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(workout)

        let _ = try? await session.data(for: request)
    }
}
