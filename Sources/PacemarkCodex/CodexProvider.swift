import Foundation
import PacemarkKit

/// Reads limits through a fresh local app-server using Codex's persistent
/// ChatGPT login. It never starts a model turn or handles credentials.
public nonisolated struct CodexProvider: Provider {
    public let id = "codex"
    public let name = "Codex"
    private let executable: URL?
    private let homeDirectory: URL
    private let timeout: Duration

    public init() {
        executable = nil
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        timeout = .seconds(30)
    }

    init(executable: URL, homeDirectory: URL, timeout: Duration) {
        self.executable = executable
        self.homeDirectory = homeDirectory
        self.timeout = timeout
    }

    @concurrent public func fetch() async -> FetchResult {
        do {
            let located = if let executable { executable } else { await CodexLocator.locate(homeDirectory: homeDirectory) }
            guard let binary = located, FileManager.default.isExecutableFile(atPath: binary.path) else {
                return .problem(.codexNotFound)
            }
            let environment = CodexLocator.environment(homeDirectory: homeDirectory, binary: binary)
            let version = try await CodexProcess.output(executable: binary, arguments: ["--version"],
                directory: homeDirectory, environment: environment, timeout: .seconds(5))
            guard version.trimmingCharacters(in: .whitespacesAndNewlines) == "codex-cli 0.162.1" else {
                return .problem(.codexVersion)
            }
            let child = try CodexProcess(executable: binary, arguments: ["app-server", "--listen", "stdio://"],
                                         directory: homeDirectory, environment: environment)
            return try await child.perform(timeout: timeout) {
                var rpc = CodexExchange(child)
                _ = try await rpc.request("initialize", id: 1,
                    params: #"{"clientInfo":{"name":"pacemark","title":"Pacemark","version":"0.1.0"}}"#, as: Initialization.self)
                try child.send(#"{"method":"initialized","params":{}}"#)
                let account = try await rpc.request("account/read", id: 2,
                                                    params: #"{"refreshToken":false}"#, as: AccountResponse.self)
                guard account.account?.type == "chatgpt" else { return .problem(.codexLogin) }
                var identity = ProviderIdentity(email: account.account?.email, accountID: account.workspaceRouting?.chatgptAccountId)
                do {
                    let rates = try await rpc.request("account/rateLimits/read", id: 3, as: RateLimitsResponse.self)
                    identity = ProviderIdentity(email: account.account?.email, accountID: rates.accountId ?? identity.accountID)
                    // Check again before accepting a response from an account
                    // that may have switched while the request was in flight.
                    let after = try await rpc.request("account/read", id: 2,
                        params: #"{"refreshToken":false}"#, as: AccountResponse.self)
                    guard after.account?.type == "chatgpt" else { return .problem(.codexLogin) }
                    let current = ProviderIdentity(email: after.account?.email,
                        accountID: after.workspaceRouting?.chatgptAccountId ?? identity.accountID)
                    guard current == identity else {
                        return .unavailableForAccount(current, discardPrevious: true)
                    }
                    return .limits(try rates.limits(), identity: identity)
                } catch CodexError.incompatible {
                    return .problem(.codexResponse)
                } catch CodexError.rpc(let code, let message) {
                    return Self.failure(code: code, message: message, identity: identity)
                } catch {
                    return .unavailableForAccount(identity)
                }
            }
        } catch CodexError.incompatible {
            return .problem(.codexResponse)
        } catch CodexError.rpc(let code, let message) {
            return Self.failure(code: code, message: message, identity: nil)
        } catch {
            return .unavailable
        }
    }

    private static func failure(code: Int, message: String, identity: ProviderIdentity?) -> FetchResult {
        if code == -32601 || code == -32602 { return .problem(.codexResponse) }
        let text = message.lowercased()
        if code == 401 || text.contains("unauthorized") || text.contains("not authenticated")
            || text.contains("not logged in") || text.contains("requires chatgpt") || text.contains("sign in") {
            return .problem(.codexLogin)
        }
        return identity.map { .unavailableForAccount($0) } ?? .unavailable
    }
}

private nonisolated struct Initialization: Decodable, Sendable { let userAgent: String }
nonisolated struct AccountResponse: Decodable, Sendable {
    let account: Account?
    let workspaceRouting: WorkspaceRouting?
    struct WorkspaceRouting: Decodable, Sendable { let chatgptAccountId: String }
    struct Account: Decodable, Sendable { let type: String; let email: String? }
}

nonisolated extension Problem {
    static let codexNotFound = Problem(heading: "Codex CLI not found",
        message: "Install the Codex CLI, then run `codex login` in Terminal and sign in with ChatGPT.",
        link: ProblemLink(title: "Install Codex", url: URL(string: "https://learn.chatgpt.com/docs/cli")!))
    static let codexLogin = Problem(heading: "Sign in to Codex with ChatGPT",
        message: "Run `codex login` in Terminal and sign in with ChatGPT. Pacemark needs the CLI's persistent ChatGPT login.", link: nil)
    static let codexVersion = Problem(heading: "Unsupported Codex CLI version",
        message: "This Pacemark version supports Codex CLI 0.162.1. Install it with `npm install -g @openai/codex@0.162.1`, or check for a newer Pacemark release.",
        link: ProblemLink(title: "Pacemark releases", url: URL(string: "https://github.com/chris-metz/pacemark/releases")!))
    static let codexResponse = Problem(heading: "Can't read Codex limits",
        message: "Codex returned an incompatible response. Check for a newer Pacemark release and use a supported Codex CLI version.",
        link: ProblemLink(title: "Pacemark releases", url: URL(string: "https://github.com/chris-metz/pacemark/releases")!))
}
