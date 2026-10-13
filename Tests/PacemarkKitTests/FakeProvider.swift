import Foundation
import PacemarkKit
import Testing

/// A provider that answers each query with the next scripted result.
@MainActor final class FakeProvider: Provider {
    let id: String
    let name: String
    private var results: [FetchResult]
    /// How many queries it answered.
    private(set) var fetchCount = 0

    init(_ results: FetchResult..., id: String = "fake") {
        self.id = id
        name = id.capitalized
        self.results = results
    }

    func fetch() async -> FetchResult {
        fetchCount += 1
        guard !results.isEmpty else {
            Issue.record("Query \(fetchCount) has no scripted result")
            return .unavailable
        }
        return results.removeFirst()
    }
}

/// A model whose first query, at `now`, got `result`. Its timer is under
/// the test's control and never fires.
func model(
    after result: FetchResult, settings: PacemarkKit.Settings = PacemarkKit.Settings(), at now: Date
) async -> AppModel {
    let timer = FakeTimer()
    let model = AppModel(provider: FakeProvider(result), clock: { now }, sleep: { try await timer.sleep($0) })
    var enabled = settings
    enabled.enabledProviderIDs = ["fake"]
    model.settings = enabled
    model.launch()
    _ = await timer.armed()
    return model
}

/// Existing single-provider regression fixtures explicitly opt in.
extension AppModel {
    convenience init(provider: any Provider, settingsStore: SettingsStore? = nil,
                     clock: @escaping () -> Date = { Date() },
                     sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.init(providers: [provider], settingsStore: settingsStore, clock: clock, sleep: sleep)
        settings.enabledProviderIDs = [provider.id]
    }
    var state: ProviderState { state(for: providers[0].id) }
    var display: Display { providerDisplay(for: providers[0].id) }
    func setLimit(_ limit: Limit, shownInDropdown: Bool) {
        setLimit(limit, providerID: providers[0].id, shownInDropdown: shownInDropdown)
    }
    func isLimitShownInDropdown(_ limit: Limit) -> Bool {
        settings.isLimitShownInDropdown(limit, providerID: providers[0].id)
    }
}
