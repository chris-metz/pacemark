import Foundation
import PacemarkKit
import Testing

/// Recording how a query ended (§6.4), with fixed dates.
@Suite struct ProviderStateTests {
    @Test func aDifferentPersonInTheSameWorkspaceClearsCachedLimitsOnFailure() {
        var state = ProviderState()
        state.record(.limits(claudeLimits, identity: ProviderIdentity(email: "one@example.test", accountID: "team")), finishedAt: beforeTheResets)
        state.record(.unavailableForAccount(ProviderIdentity(email: "two@example.test", accountID: "team")), finishedAt: beforeTheResets + 60)
        #expect(state.limits == nil)
        #expect(state.lastSuccessAt == nil)
        #expect(state.lastOutcome == .unavailable)
    }

    let earlier = Date(timeIntervalSince1970: 1_789_990_000)
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func successStoresTheLimitsAndEndsTheFailureStreak() {
        var state = ProviderState(lastAttemptAt: earlier, lastOutcome: .unavailable, failureStreak: 2, isQuerying: true)

        state.record(.limits(claudeLimits), finishedAt: now)

        #expect(state == ProviderState(
            lastAttemptAt: now, lastOutcome: .success, limits: claudeLimits, lastSuccessAt: now, failureStreak: 0,
            isQuerying: false
        ))
    }

    @Test func temporaryErrorKeepsTheLimitsAndRaisesTheFailureStreak() {
        var state = ProviderState(
            lastAttemptAt: earlier, lastOutcome: .success, limits: claudeLimits, lastSuccessAt: earlier, failureStreak: 0,
            isQuerying: true
        )

        state.record(.unavailable, finishedAt: now)

        #expect(state == ProviderState(
            lastAttemptAt: now, lastOutcome: .unavailable, limits: claudeLimits, lastSuccessAt: earlier, failureStreak: 1,
            isQuerying: false
        ))
    }

    @Test func problemClearsTheLimitsAndEndsTheFailureStreak() {
        var state = ProviderState(
            lastAttemptAt: earlier, lastOutcome: .unavailable, limits: claudeLimits, lastSuccessAt: earlier,
            failureStreak: 2, isQuerying: true
        )

        state.record(.problem(notLoggedIn), finishedAt: now)

        #expect(state == ProviderState(
            lastAttemptAt: now, lastOutcome: .problem(notLoggedIn), limits: nil, lastSuccessAt: earlier, failureStreak: 0,
            isQuerying: false
        ))
    }
}

extension ProviderStateTests {
    @Test func aFailedReadWithoutWorkspaceIdentityRetainsTheSamePersonsReading() {
        var state = ProviderState()
        state.record(.limits(claudeLimits, identity: ProviderIdentity(email: "one@example.test", accountID: "team")), finishedAt: beforeTheResets)
        state.record(.unavailableForAccount(ProviderIdentity(email: "one@example.test", accountID: nil)), finishedAt: beforeTheResets + 60)
        #expect(state.limits == claudeLimits)
        #expect(state.lastSuccessAt == beforeTheResets)
    }
}
