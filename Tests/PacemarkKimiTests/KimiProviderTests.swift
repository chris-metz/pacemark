import Foundation
import PacemarkKit
@testable import PacemarkKimi
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1))) struct KimiProviderTests {
    @Test func readsThePlanLimitsThroughTheInstalledCLIsLocalServer() async throws {
        let cli = try ScriptedKimi()
        let result = await cli.provider.fetch()
        guard case .limits(let limits, let identity) = result else {
            Issue.record("Expected limits, got \(result)")
            return
        }
        #expect(limits.map(\.id) == ["limit5h", "limit7d", "monthTotal"])
        #expect(limits.map(\.title) == ["5-hour limit", "Weekly limit", "Monthly limit"])
        #expect(limits.map { $0.window?.utilization } == [25, 50, 40])
        #expect(limits.map { $0.window?.resetsAt }
            == [date("2026-01-15T18:30:00Z"), date("2026-01-19T09:00:00.250Z"), date("2026-02-10T00:00:00Z")])
        // 5 hours, 7 days, and 10 January to 10 February.
        #expect(limits.map(\.windowLength) == [18000, 604800, 2_678_400])
        #expect(limits.filter(\.isOverviewLimit).map(\.id) == ["limit7d"])
        #expect(limits.allSatisfy { $0.resetBehavior == .awaitReading })
        #expect(identity == ProviderIdentity(email: "one@example.test", accountID: "user-a"))
        #expect(cli.requests == [
            "http://127.0.0.1:4242/api/v1/oauth/userinfo?provider=managed:kimi-code test-token",
            "http://127.0.0.1:4242/api/v1/oauth/usage?provider=managed:kimi-code test-token",
            "http://127.0.0.1:4242/api/v1/oauth/userinfo?provider=managed:kimi-code test-token",
        ])
    }
}

/// A real child process at the CLI boundary that prints the local server's
/// ready line, plus scripted answers from that server. No real login.
nonisolated final class ScriptedKimi: Sendable {
    static let readyLine = "Kimi server: http://127.0.0.1:4242/#token=test-token"
    static let userA = #"{"code":0,"msg":"success","data":{"kind":"ok","userInfo":{"userId":"user-a","nickname":"One","email":"one@example.test","status":"normal","region":"global"}},"request_id":"01TEST"}"#

    let directory: URL
    let executable: URL
    private let answers: Mutex<(limits: (Int, String), userinfo: [(Int, String)], requests: [String])>

    var provider: KimiProvider {
        KimiProvider(executable: executable, homeDirectory: directory, timeout: .seconds(2), transport: { [self] url, token in
            answer(url, token: token)
        })
    }

    var requests: [String] { answers.withLock { $0.requests } }

    /// `behavior` replaces printing the ready line and waiting for SIGTERM.
    init(limits: String? = nil, limitsStatus: Int = 200, userinfo: String = ScriptedKimi.userA,
         userinfoAfter: String? = nil, behavior: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pacemark-kimi-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appending(path: "kimi")
        answers = Mutex(((limitsStatus, try limits ?? fixture("limits")),
                         [(200, userinfo), (200, userinfoAfter ?? userinfo)], []))
        let script = """
        #!/bin/sh
        echo $$ > server.pid
        printf '%s\\n' "$*" > arguments
        env > environment
        \(behavior ?? "printf '%s\\n' '\(Self.readyLine)'; trap 'exit 0' TERM; sleep 20 & wait")
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    private func answer(_ url: URL, token: String) -> (status: Int, body: Data) {
        answers.withLock { state in
            state.requests.append("\(url.absoluteString) \(token)")
            let (status, body) = url.path.hasSuffix("/usage") ? state.limits
                : state.userinfo.count > 1 ? state.userinfo.removeFirst() : state.userinfo[0]
            return (status, Data(body.utf8))
        }
    }
}

nonisolated func fixture(_ name: String) throws -> String {
    try String(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!, encoding: .utf8)
}

nonisolated func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = iso.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    return formatter.date(from: iso)!
}

extension KimiProviderTests {
    @Test(arguments: ["no-weekly", "no-5h", "no-reset", "over-100", "empty"])
    func incompleteAnswersKeepTheirMeaning(fixture name: String) async throws {
        let cli = try ScriptedKimi(limits: fixture(name))
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits for \(name)"); return
        }
        switch name {
        case "no-weekly":
            #expect(limits.map(\.id) == ["limit5h", "monthTotal"])
            #expect(limits.filter(\.isOverviewLimit).map(\.id) == ["monthTotal"])
        case "no-5h":
            #expect(limits.map(\.id) == ["limit7d", "monthTotal"])
            #expect(limits.filter(\.isOverviewLimit).map(\.id) == ["limit7d"])
        case "no-reset":
            #expect(limits.first?.window == ActiveWindow(utilization: 40, resetsAt: nil))
            #expect(limits.first?.windowLength == nil)
            #expect(limits.first?.isOverviewLimit == true)
        case "over-100":
            #expect(limits.first?.window?.utilization == 125)
        default:
            #expect(limits.isEmpty)
        }
    }

    @Test(arguments: [
        ("2026-11-25T00:00:00Z", 31.0),  // from 25 October
        ("2026-07-15T12:30:00Z", 30.0),  // from 15 June, 12:30
        ("2026-03-01T00:00:00Z", 28.0),  // from 1 February
        ("2028-03-01T00:00:00Z", 29.0),  // leap year
        ("2026-03-31T00:00:00Z", 31.0),  // from 28 February, the last day
        ("2026-05-31T00:00:00Z", 31.0),  // from 30 April, the last day
    ])
    func theMonthlyWindowIsTheCalendarMonthBeforeTheReset(reset: String, days: Double) async throws {
        let limits = #"{"code":0,"msg":"success","data":{"kind":"ok","quota":{"usages":{"monthTotal":{"usedRatio":0.1,"resetAt":"\#(reset)"}}}}}"#
        let cli = try ScriptedKimi(limits: limits)
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits"); return
        }
        #expect(limits.first?.windowLength == days * 86400)
    }
}

extension KimiProviderTests {
    static let userA = ProviderIdentity(email: "one@example.test", accountID: "user-a")

    @Test func withoutALoginKimiAsksToSignIn() async throws {
        let cli = try ScriptedKimi(userinfo: fixture("not-logged-in"))
        #expect(await cli.provider.fetch() == .problem(.kimiLogin))
    }

    @Test func aRejectedLoginAsksToSignIn() async throws {
        let cli = try ScriptedKimi(limits: fixture("unauthorized"))
        #expect(await cli.provider.fetch() == .problem(.kimiLogin))
    }

    @Test(arguments: ["service-error", "server-error"])
    func serviceFailureRetainsTheIdentity(fixture name: String) async throws {
        let cli = try ScriptedKimi(limits: fixture(name))
        #expect(await cli.provider.fetch() == .unavailableForAccount(Self.userA))
    }

    @Test func aServerErrorStatusRetainsTheIdentity() async throws {
        let cli = try ScriptedKimi(limits: "Bad gateway", limitsStatus: 502)
        #expect(await cli.provider.fetch() == .unavailableForAccount(Self.userA))
    }

    @Test(arguments: ["malformed-reset", "negative-ratio", "unknown-kind", "no-data"])
    func anUnreadableAnswerHasAnIncompatibleResponseMessage(fixture name: String) async throws {
        let cli = try ScriptedKimi(limits: fixture(name))
        #expect(await cli.provider.fetch() == .problem(.kimiResponse))
    }

    @Test(arguments: [(404, #"{"message":"Route GET:/api/v1/oauth/usage not found"}"#), (200, "not-json")])
    func aMissingRouteOrNonJSONHasAnIncompatibleResponseMessage(status: Int, body: String) async throws {
        let cli = try ScriptedKimi(limits: body, limitsStatus: status)
        #expect(await cli.provider.fetch() == .problem(.kimiResponse))
    }

    @Test func anAccountSwitchDuringTheRequestDiscardsTheResponse() async throws {
        let userB = ScriptedKimi.userA.replacingOccurrences(of: "user-a", with: "user-b")
            .replacingOccurrences(of: "one@", with: "two@")
        let cli = try ScriptedKimi(userinfoAfter: userB)
        #expect(await cli.provider.fetch()
            == .unavailableForAccount(ProviderIdentity(email: "two@example.test", accountID: "user-b"), discardPrevious: true))
    }
}

extension KimiProviderTests {
    @Test func theServerRunsOnAFreeLoopbackPortWithoutTelemetryOrInheritedOverrides() async throws {
        let cli = try ScriptedKimi()
        _ = await cli.provider.fetch()
        let arguments = try String(contentsOf: cli.directory.appending(path: "arguments"), encoding: .utf8)
        #expect(arguments == "web --no-open --port 0 --log-level warn\n")
        let environment = try String(contentsOf: cli.directory.appending(path: "environment"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(environment.filter { $0.hasPrefix("KIMI") } == ["KIMI_DISABLE_TELEMETRY=1"])
        #expect(environment.contains("PATH=\(cli.directory.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
    }

    @Test func aWellBehavedServerIsStoppedGracefully() async throws {
        let cli = try ScriptedKimi(behavior: "printf '%s\\n' '\(ScriptedKimi.readyLine)'; "
            + "trap 'sleep 0.3; echo TERM > stopped; exit 0' TERM; sleep 20 & wait")
        _ = await cli.provider.fetch()
        // SIGTERM, and time to finish, let the real server release its
        // registration and flush its indexes.
        #expect(try String(contentsOf: cli.directory.appending(path: "stopped"), encoding: .utf8) == "TERM\n")
    }

    @Test(arguments: ["exit 3", "printf 'Kimi server: not a url\\n'", "printf 'Kimi server: http://127.0.0.1:4242/\\n'"])
    func aServerThatNeverReportsWhereItListensHasAnIncompatibleResponseMessage(behavior: String) async throws {
        let cli = try ScriptedKimi(behavior: behavior)
        #expect(await cli.provider.fetch() == .problem(.kimiResponse))
    }

    @Test(arguments: ["trap '' TERM; sleep 20 & wait",
                      "printf '%s\\n' '\(ScriptedKimi.readyLine)'; trap '' TERM; sleep 20 & wait"])
    func unresponsiveProcessesFinishAndAreCleanedUp(behavior: String) async throws {
        let cli = try ScriptedKimi(behavior: behavior)
        let result = await cli.provider.fetch()
        if behavior.hasPrefix("trap") { #expect(result == .unavailable) }
        let pid = try Int32(String(contentsOf: cli.directory.appending(path: "server.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(kill(try #require(pid), 0) == -1)
    }

    @Test func cancellationStopsTheProcessGroup() async throws {
        let cli = try ScriptedKimi(behavior: "trap '' TERM; sleep 20 & wait")
        let provider = cli.provider
        let task = Task { await provider.fetch() }
        let pidURL = cli.directory.appending(path: "server.pid")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try #require(Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        #expect(await task.value == .unavailable)
        #expect(kill(pid, 0) == -1)
    }

    @Test func missingInstallationHasInstructions() async {
        let provider = KimiProvider(executable: URL(filePath: "/nonexistent/pacemark-test-kimi"),
                                    homeDirectory: FileManager.default.temporaryDirectory, timeout: .seconds(1),
                                    transport: { _, _ in (500, Data()) })
        #expect(await provider.fetch() == .problem(.kimiNotFound))
    }
}

extension KimiProviderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACEMARK_LIVE_KIMI"] == "1"))
    func installedCLICompatibility() async {
        let result = await KimiProvider().fetch()
        // Do not print account identity or usage in the test log.
        switch result {
        case .limits(let limits, _): #expect(!limits.isEmpty)
        case .problem(let problem): Issue.record(Comment(rawValue: problem.heading))
        case .unavailable: Issue.record("CLI unavailable before account identification")
        case .unavailableForAccount: Issue.record("Limits unavailable after account identification")
        }
    }
}
