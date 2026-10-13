import Foundation
import PacemarkKit
import Testing

@Suite struct IncompleteLimitTests {
    @Test func anExpiredCodexReadingWaitsWithoutInventingZero() {
        let limit = Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                          window: ActiveWindow(utilization: 42, resetsAt: Date(timeIntervalSince1970: 1000)),
                          resetBehavior: .awaitReading, isGeneralWeekly: true)
        let result = limitDisplay(limit, now: Date(timeIntervalSince1970: 1000))
        #expect(result.state == .waitingForUpdate)
        #expect(result.percentText.isEmpty)
        #expect(result.resetLine == "Waiting for updated limits")
        #expect(result.paceMarker == nil)
        #expect(result.paceText == nil)
    }

    @Test func codexQueriesAtResetWhileClaudeKeepsIts65SecondDelay() {
        let reset = Date(timeIntervalSince1970: 2000)
        let codex = Limit(id: "weekly", title: "Weekly", windowLength: 604800,
                          window: ActiveWindow(utilization: 80, resetsAt: reset), resetBehavior: .awaitReading)
        let claude = Limit(id: "weekly", title: "Weekly", windowLength: 604800,
                           window: ActiveWindow(utilization: 80, resetsAt: reset))
        let last = Date(timeIntervalSince1970: 1900)
        #expect(nextQueryAt(succeeded([codex], at: last), interval: 300, now: last) == reset)
        #expect(nextQueryAt(succeeded([claude], at: last), interval: 300, now: last) == reset + 65)
        let result = display(failed(after: [codex], age: 1500), providerID: "codex", settings: Settings(menuBarLimitID: "codex/weekly"), now: reset)
        #expect(result.menuBar.content == .glyph())
    }

    @Test func knownUtilizationWithoutResetKeepsItsBarWithoutPace() {
        let limit = Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                          window: ActiveWindow(utilization: 42, resetsAt: nil),
                          resetBehavior: .awaitReading, isGeneralWeekly: true)
        let result = limitDisplay(limit, now: Date(timeIntervalSince1970: 1000))
        #expect(result.percentText == "42%")
        #expect(result.fillFraction == 0.42)
        #expect(result.resetLine == "Reset time unavailable")
        #expect(result.paceMarker == nil)
        #expect(result.paceText == nil)
    }
}
