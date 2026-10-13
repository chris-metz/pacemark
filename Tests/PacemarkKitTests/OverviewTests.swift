import Foundation
import PacemarkKit
import Testing

@Suite struct OverviewTests {
    @Test func overviewKeepsAHiddenGeneralWeeklyLimitAndExcludesModelLimits() {
        let weekly = Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                           window: ActiveWindow(utilization: 42, resetsAt: nil), isGeneralWeekly: true)
        let model = Limit(id: "model", title: "Model limit", windowLength: 604800,
                          window: ActiveWindow(utilization: 91, resetsAt: nil))
        let state = succeeded([model, weekly], at: now)
        let entry = overviewEntry(state, providerID: "codex", providerName: "Codex",
                                  settings: Settings(hiddenLimits: ["codex/weekly"]), now: now)
        #expect(entry.content == .limit(weekly))
        #expect(entry.updateLine == "Updated just now")
    }
}
