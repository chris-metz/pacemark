import Foundation
import PacemarkKit
@testable import PacemarkCodex
import Testing

@Suite(.timeLimit(.minutes(1))) struct CodexProviderTests {
    @Test func readsGeneralAndModelWindowsThroughTheInstalledCLI() async throws {
        let cli = try ScriptedCodex()
        let result = await cli.provider.fetch()
        guard case .limits(let limits, _) = result else {
            Issue.record("Expected limits, got \(result)")
            return
        }
        #expect(limits.map(\.id) == ["primary", "secondary", "model:model-x/primary"])
        #expect(limits.map { $0.window?.utilization } == [12, 42, 73])
        #expect(limits.filter(\.isOverviewLimit).map(\.id) == ["secondary"])
        #expect(limits[1].windowLength == 604800)
    }
}

/// A real child process at the CLI boundary. It serves documented JSON-RPC
/// responses and rejects unexpected methods, without accessing a real login.
final class ScriptedCodex {
    let directory: URL
    let executable: URL
    var provider: CodexProvider { CodexProvider(executable: executable, homeDirectory: directory, timeout: .seconds(2)) }

    init(limits: String? = nil, account: String = #"{"account":{"type":"chatgpt","email":"one@example.test","planType":"pro"}}"#,
         version: String = "codex-cli 0.162.1", behavior: String = "",
         rateError: String? = nil, accountAfter: String? = nil, notification: String = "") throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pacemark-codex-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appending(path: "codex")
        let rates = try limits ?? String(contentsOf: Bundle.module.url(forResource: "limits", withExtension: "json", subdirectory: "Fixtures")!, encoding: .utf8)
        try rates.trimmingCharacters(in: .whitespacesAndNewlines).write(to: directory.appending(path: "limits.json"), atomically: true, encoding: .utf8)
        let rateReply = rateError.map { "printf '%s\\n' '{\"id\":3,\"error\":\($0)}'" }
            ?? "printf '{\"id\":3,\"result\":'; cat limits.json; printf '}\\n'"
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '%s\\n' '\(version)'; exit; fi
        echo $$ > server.pid
        account_reads=0
        \(behavior)
        while IFS= read -r request; do
            case "$request" in
                *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{"userAgent":"codex/0.162.1"}}' ;;
                *'"method":"initialized"'*) ;;
                *'"method":"account/read"'*)
                    account_reads=$((account_reads + 1))
                    if [ "$account_reads" = 1 ]; then
                        printf '%s\\n' '{"id":2,"result":\(account)}'
                    else
                        printf '%s\\n' '{"id":2,"result":\(accountAfter ?? account)}'
                    fi ;;

                *'"method":"account/rateLimits/read"'*) \(notification)
                    \(rateReply) ;;
                *) exit 4 ;;
            esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}


extension CodexProviderTests {
    @Test(arguments: ["unknown-reset", "unknown-duration", "weekly-primary", "ambiguous-weekly", "no-general", "legacy-model", "empty", "expired"])
    func incompleteAndAdditionalWindowsKeepTheirMeaning(fixture: String) async throws {
        let json = try String(contentsOf: Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!, encoding: .utf8)
        let cli = try ScriptedCodex(limits: json)
        guard case .limits(let limits, _) = await cli.provider.fetch() else {
            Issue.record("Expected limits for \(fixture)"); return
        }
        switch fixture {
        case "unknown-reset":
            #expect(limits.first?.window?.utilization == 42)
            #expect(limits.first?.window?.resetsAt == nil)
            #expect(limits.first?.isOverviewLimit == true)
        case "unknown-duration":
            #expect(limits.first?.windowLength == nil)
            #expect(limits.first?.isOverviewLimit == false)
        case "weekly-primary":
            #expect(limits.filter(\.isOverviewLimit).map(\.id) == ["primary"])
            #expect(limits.first?.windowLength == 600000)
        case "ambiguous-weekly":
            #expect(limits.count == 2)
            #expect(limits.filter(\.isOverviewLimit).isEmpty)
        case "no-general", "legacy-model":
            #expect(limits.map(\.id) == ["model:model-x/primary"])
            #expect(limits.filter(\.isOverviewLimit).isEmpty)
        case "expired":
            let row = limitDisplay(try #require(limits.first), now: Date(timeIntervalSince1970: 2000))
            #expect(row.state == .waitingForUpdate)
        default: #expect(limits.isEmpty)
        }
    }

    @Test(arguments: [#"{"account":null}"#, #"{"account":{"type":"apiKey"}}"#, #"{"account":{"type":"chatgptAuthTokens"}}"#])
    func missingOrUnsuitableLoginHasSetupInstructions(account: String) async throws {
        let cli = try ScriptedCodex(account: account)
        #expect(await cli.provider.fetch() == .problem(.codexLogin))
    }

    @Test(arguments: ["codex-cli 0.161.0", "codex-cli 0.163.0", "codex-cli 1.0.0", "unknown version"])
    func anyVersionWithACompatibleResponseIsRead(version: String) async throws {
        let cli = try ScriptedCodex(version: version)
        if case .limits = await cli.provider.fetch() {} else { Issue.record("\(version) should be read") }
    }

    @Test func anUnknownMethodHasAnIncompatibleResponseMessage() async throws {
        let cli = try ScriptedCodex(rateError: #"{"code":-32601,"message":"Method not found"}"#)
        #expect(await cli.provider.fetch() == .problem(.codexResponse))
    }

    @Test func aMalformedWindowHasAnIncompatibleResponseMessage() async throws {
        let json = try String(contentsOf: Bundle.module.url(forResource: "malformed", withExtension: "json", subdirectory: "Fixtures")!, encoding: .utf8)
        let cli = try ScriptedCodex(limits: json)
        #expect(await cli.provider.fetch() == .problem(.codexResponse))
    }

    @Test func authenticationErrorsAskForChatGPTLogin() async throws {
        let cli = try ScriptedCodex(rateError: #"{"code":401,"message":"Unauthorized"}"#)
        #expect(await cli.provider.fetch() == .problem(.codexLogin))
    }

    @Test func serviceFailureRetainsTheAvailableIdentity() async throws {
        let cli = try ScriptedCodex(rateError: #"{"code":-32000,"message":"Service unavailable"}"#)
        #expect(await cli.provider.fetch() == .unavailableForAccount(ProviderIdentity(email: "one@example.test", accountID: nil)))
    }

    @Test func anAccountSwitchDuringTheRequestDiscardsTheResponse() async throws {
        let cli = try ScriptedCodex(accountAfter: #"{"account":{"type":"chatgpt","email":"two@example.test"}}"#)
        #expect(await cli.provider.fetch() == .unavailableForAccount(ProviderIdentity(email: "two@example.test", accountID: "workspace-a"), discardPrevious: true))
    }

    @Test func ordinaryAccountNotificationsKeepTheVerifiedReading() async throws {
        let cli = try ScriptedCodex(notification: #"printf '%s\n' '{"method":"account/updated","params":{"authMode":"chatgpt"}}';"#)
        if case .limits = await cli.provider.fetch() {} else { Issue.record("An unchanged account should keep its reading") }
    }

    @Test(arguments: ["exit 3", "printf 'not-json\\n'", "trap '' TERM; sleep 20 & wait"])
    func brokenOrUnresponsiveProcessesFinishAndAreCleanedUp(behavior: String) async throws {
        let cli = try ScriptedCodex(behavior: behavior)
        let result = await cli.provider.fetch()
        #expect(result == .unavailable || result == .problem(.codexResponse))
        let pid = try Int32(String(contentsOf: cli.directory.appending(path: "server.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(kill(try #require(pid), 0) == -1)
    }

    @Test func cancellationStopsTheProcessGroup() async throws {
        let cli = try ScriptedCodex(behavior: "trap '' TERM; sleep 20 & wait")
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
}

extension CodexProviderTests {
    @Test func missingInstallationHasInstructions() async {
        let provider = CodexProvider(executable: URL(filePath: "/nonexistent/pacemark-test-codex"),
                                     homeDirectory: FileManager.default.temporaryDirectory, timeout: .seconds(1))
        #expect(await provider.fetch() == .problem(.codexNotFound))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACEMARK_LIVE_CODEX"] == "1"))
    func installedCLICompatibility() async {
        let result = await CodexProvider().fetch()
        // Do not print account identity or usage in the test log.
        switch result {
        case .limits: break
        case .problem(let problem): Issue.record(Comment(rawValue: problem.heading))
        case .unavailable: Issue.record("CLI unavailable before account identification")
        case .unavailableForAccount: Issue.record("Limits unavailable after account identification")
        }
    }
}
