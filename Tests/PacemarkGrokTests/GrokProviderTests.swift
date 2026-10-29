import Foundation
import PacemarkKit
@testable import PacemarkGrok
import Testing

@Suite(.timeLimit(.minutes(1))) struct GrokProviderTests {
    @Test func readsTheSubscriptionLimitThroughTheInstalledCLIsAgent() async throws {
        let cli = try ScriptedGrok()
        let result = await cli.provider.fetch()
        guard case .limits(let limits, let identity) = result else {
            Issue.record("Expected limits, got \(result)")
            return
        }
        #expect(limits == [Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                                 window: ActiveWindow(utilization: 42, resetsAt: date("2026-01-19T09:00:00Z")),
                                 resetBehavior: .awaitReading, isOverviewLimit: true)])
        #expect(identity == ProviderIdentity(email: "one@example.test", accountID: "user-a"))
        #expect(try cli.methods() == ["initialize", "_x.ai/auth/info", "_x.ai/billing", "_x.ai/auth/info"])
    }
}

/// A real child process at the CLI boundary. It answers Grok's agent
/// methods over stdio with scripted replies, without a real login.
nonisolated final class ScriptedGrok: Sendable {
    static let userA = #"{"methodId":"cached_token","email":"one@example.test","firstName":"One","principalType":"User","principalId":"user-a","teamId":"team-a"}"#

    let directory: URL
    let executable: URL

    var provider: GrokProvider {
        GrokProvider(executable: executable, homeDirectory: directory, timeout: .seconds(2))
    }

    /// `billing` and `auth` are the replies' `result` or `error` members.
    /// `behavior` runs before the request loop; `notification` is printed
    /// before each answer.
    init(billing: String? = nil, auth: String = #""result":\#(ScriptedGrok.userA)"#, authAfter: String? = nil,
         behavior: String = "", notification: String = "", afterInput: String = "") throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pacemark-grok-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appending(path: "grok")
        try write(billing ?? #""result":\#(fixture("limits"))"#, to: "billing")
        try write(auth, to: "auth")
        try write(authAfter ?? auth, to: "auth-after")
        let script = """
        #!/bin/sh
        dir=$(dirname "$0")
        echo $$ > "$dir/server.pid"
        printf '%s\\n' "$*" > "$dir/arguments"
        env > "$dir/environment"
        pwd > "$dir/directory"
        ls -A > "$dir/directory-contents"
        \(behavior)
        auth_reads=0
        while IFS= read -r request; do
            printf '%s\\n' "$request" >> "$dir/requests"
            id=$(printf '%s' "$request" | sed -E 's/.*"id":([0-9]+).*/\\1/')
            case "$request" in
                *'"method":"initialize"'*) reply='"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}' ;;
                *'"method":"_x.ai/auth/info"'*)
                    auth_reads=$((auth_reads + 1))
                    if [ "$auth_reads" = 1 ]; then reply=$(cat "$dir/auth"); else reply=$(cat "$dir/auth-after"); fi ;;
                *'"method":"_x.ai/billing"'*) reply=$(cat "$dir/billing") ;;
                *) reply='"error":{"code":-32601,"message":"Method not found"}' ;;
            esac
            \(notification)
            printf '{"jsonrpc":"2.0","id":%s,%s}\\n' "$id" "$reply"
        done
        echo EOF > "$dir/stopped"
        \(afterInput)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// The methods Pacemark called, in order. Every request is JSON-RPC 2.0.
    func methods() throws -> [String] {
        try String(contentsOf: directory.appending(path: "requests"), encoding: .utf8)
            .split(separator: "\n").map { line in
                let request = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                #expect(request["jsonrpc"] as? String == "2.0")
                return try #require(request["method"] as? String)
            }
    }

    func recorded(_ name: String) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    /// One line, so the reply stays one JSON-RPC message.
    private func write(_ member: String, to name: String) throws {
        try member.replacingOccurrences(of: "\n", with: "").write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
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

extension GrokProviderTests {
    @Test func aMonthlyPeriodBecomesTheMonthlyLimit() async throws {
        let cli = try ScriptedGrok(billing: #""result":\#(fixture("monthly"))"#)
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits"); return
        }
        // 10 January to 10 February.
        #expect(limits == [Limit(id: "monthly", title: "Monthly limit", windowLength: 2_678_400,
                                 window: ActiveWindow(utilization: 18.5, resetsAt: date("2026-02-10T00:00:00Z")),
                                 resetBehavior: .awaitReading, isOverviewLimit: true)])
    }
}

extension GrokProviderTests {
    @Test(arguments: ["unknown-type", "end-before-start", "negative-percent", "string-percent", "no-percent",
                      "malformed-time", "no-config"])
    func anUnreadableAnswerHasAnIncompatibleResponseMessage(fixture name: String) async throws {
        let cli = try ScriptedGrok(billing: #""result":\#(fixture(name))"#)
        #expect(await cli.provider.fetch() == .problem(.grokResponse))
    }

    @Test(arguments: [#""error":{"code":-32601,"message":"Method not found"}"#,
                      #""error":{"code":-32602,"message":"Invalid params"}"#, #""result":"not an object""#])
    func aMissingMethodOrAnUnexpectedResultHasAnIncompatibleResponseMessage(billing: String) async throws {
        let cli = try ScriptedGrok(billing: billing)
        #expect(await cli.provider.fetch() == .problem(.grokResponse))
    }

    @Test(arguments: ["printf 'Usage: grok [OPTIONS]\\n'; exit 2", "exit 0"])
    func anAgentThatExitsBeforeItsFirstAnswerHasAnIncompatibleResponseMessage(behavior: String) async throws {
        let cli = try ScriptedGrok(behavior: behavior)
        #expect(await cli.provider.fetch() == .problem(.grokResponse))
    }
}

extension GrokProviderTests {
    @Test(arguments: ["over-100", "no-period"])
    func incompleteAnswersKeepTheirMeaning(fixture name: String) async throws {
        let cli = try ScriptedGrok(billing: #""result":\#(fixture(name))"#)
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits for \(name)"); return
        }
        switch name {
        case "over-100": #expect(limits.map { $0.window?.utilization } == [125.5])
        default: #expect(limits.isEmpty)
        }
    }
}

extension GrokProviderTests {
    static let loggedOut = #""result":{"methodId":null,"email":null,"firstName":null,"principalType":null,"principalId":null,"teamId":null}"#

    @Test func withoutALoginGrokAsksToSignIn() async throws {
        let cli = try ScriptedGrok(auth: Self.loggedOut)
        #expect(await cli.provider.fetch() == .problem(.grokLogin))
    }

    @Test func aLoginThatEndsDuringTheRequestAsksToSignIn() async throws {
        let cli = try ScriptedGrok(authAfter: Self.loggedOut)
        #expect(await cli.provider.fetch() == .problem(.grokLogin))
    }

    @Test func anExpiredLoginAsksToSignIn() async throws {
        let cli = try ScriptedGrok(billing: #""error":{"code":-32000,"message":"Authentication required","data":"Run grok login"}"#)
        #expect(await cli.provider.fetch() == .problem(.grokLogin))
    }
}

extension GrokProviderTests {
    static let userA = ProviderIdentity(email: "one@example.test", accountID: "user-a")

    @Test(arguments: [#""error":{"code":-32603,"message":"Internal error"}"#,
                      #""error":{"code":-32000,"message":"Billing error: upstream timed out"}"#])
    func aServiceFailureRetainsTheIdentity(billing: String) async throws {
        let cli = try ScriptedGrok(billing: billing)
        #expect(await cli.provider.fetch() == .unavailableForAccount(Self.userA))
    }

    @Test func anAccountSwitchDuringTheRequestDiscardsTheResponse() async throws {
        let userB = ScriptedGrok.userA.replacingOccurrences(of: "user-a", with: "user-b")
            .replacingOccurrences(of: "one@", with: "two@")
        let cli = try ScriptedGrok(authAfter: #""result":\#(userB)"#)
        #expect(await cli.provider.fetch()
            == .unavailableForAccount(ProviderIdentity(email: "two@example.test", accountID: "user-b"), discardPrevious: true))
    }
}

extension GrokProviderTests {
    @Test func theAgentRunsWithoutALeaderTelemetryOrInheritedOverridesInAnEmptyDirectory() async throws {
        let cli = try ScriptedGrok()
        _ = await cli.provider.fetch()
        #expect(try cli.recorded("arguments") == "agent --no-leader stdio\n")
        let environment = try cli.recorded("environment").split(separator: "\n").map(String.init)
        #expect(environment.filter { $0.hasPrefix("GROK") || $0.hasPrefix("XAI") } == ["GROK_TELEMETRY_ENABLED=0"])
        #expect(environment.contains("HOME=\(cli.directory.path)"))
        #expect(environment.contains("PATH=\(cli.directory.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
        // A fresh directory, so the agent loads no project configuration,
        // and it is gone afterwards.
        let directory = try cli.recorded("directory").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(filePath: directory).lastPathComponent != cli.directory.lastPathComponent)
        #expect(try cli.recorded("directory-contents").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    @Test func notificationsBetweenAnswersAreSkipped() async throws {
        let cli = try ScriptedGrok(notification: #"printf '%s\n' '{"jsonrpc":"2.0","method":"_x.ai/models/update","params":{"currentModelId":"grok-test"}}'"#)
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits"); return
        }
        #expect(limits.map(\.id) == ["weekly"])
    }
}

extension GrokProviderTests {
    @Test func theAgentEndsWhenItsInputCloses() async throws {
        let cli = try ScriptedGrok()
        _ = await cli.provider.fetch()
        #expect(try cli.recorded("stopped") == "EOF\n")
    }

    @Test func anAgentThatKeepsRunningAfterItsInputClosesIsTerminated() async throws {
        let cli = try ScriptedGrok(afterInput: #"trap 'echo TERM > "$dir/stopped"; exit 0' TERM; sleep 20 & wait"#)
        let result = await cli.provider.fetch()
        #expect(result == .limits(try #require(result.limits), identity: Self.userA))
        #expect(try cli.recorded("stopped") == "TERM\n")
    }
}

extension FetchResult {
    var limits: [Limit]? {
        if case .limits(let limits, _) = self { limits } else { nil }
    }
}

extension GrokProviderTests {
    @Test(arguments: [(behavior: "trap '' TERM; sleep 20 & wait", afterInput: ""),
                      (behavior: "", afterInput: "trap '' TERM; sleep 20 & wait")])
    func unresponsiveProcessesFinishAndAreCleanedUp(behavior: String, afterInput: String) async throws {
        let cli = try ScriptedGrok(behavior: behavior, afterInput: afterInput)
        let result = await cli.provider.fetch()
        // An agent that never answers times out; one that answered keeps its limits.
        #expect(behavior.isEmpty ? result.limits != nil : result == .unavailable)
        let pid = try #require(Int32(cli.recorded("server.pid").trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1)
    }

    @Test func cancellationStopsTheProcessGroup() async throws {
        let cli = try ScriptedGrok(behavior: "trap '' TERM; sleep 20 & wait")
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
        let provider = GrokProvider(executable: URL(filePath: "/nonexistent/pacemark-test-grok"),
                                    homeDirectory: FileManager.default.temporaryDirectory, timeout: .seconds(1))
        #expect(await provider.fetch() == .problem(.grokNotFound))
    }
}

extension GrokProviderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACEMARK_LIVE_GROK"] == "1"))
    func installedCLICompatibility() async {
        let result = await GrokProvider().fetch()
        // Do not print account identity or usage in the test log.
        switch result {
        case .limits(let limits, _): #expect(!limits.isEmpty)
        case .problem(let problem): Issue.record(Comment(rawValue: problem.heading))
        case .unavailable: Issue.record("CLI unavailable before account identification")
        case .unavailableForAccount: Issue.record("Limits unavailable after account identification")
        }
    }
}
