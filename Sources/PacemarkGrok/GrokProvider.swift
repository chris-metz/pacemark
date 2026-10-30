import Foundation
import PacemarkKit

/// Reads the subscription limit through a short-lived `grok agent` using
/// Grok's own login. It never starts a model turn or touches credentials.
public nonisolated struct GrokProvider: Provider {
    public let id = "grok"
    public let name = "Grok"
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
            let located = if let executable { executable } else { await GrokLocator.locate(homeDirectory: homeDirectory) }
            guard let binary = located, FileManager.default.isExecutableFile(atPath: binary.path) else {
                return .problem(.grokNotFound)
            }
            // The agent may load project configuration from its working
            // directory, so it gets an empty one of its own.
            let directory = FileManager.default.temporaryDirectory.appending(path: "pacemark-grok-agent-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            // No shared leader process: Pacemark neither starts nor joins one.
            let child = try GrokProcess(executable: binary, arguments: ["agent", "--no-leader", "stdio"], directory: directory,
                                        environment: GrokLocator.environment(homeDirectory: homeDirectory, binary: binary))
            return try await child.perform(timeout: timeout) {
                var rpc = GrokExchange(child)
                _ = try await rpc.request("initialize", id: 1, params: #"{"protocolVersion":1,"clientCapabilities":{}}"#,
                                          as: Initialization.self)
                guard let identity = try await rpc.request("_x.ai/auth/info", id: 2, as: AuthInfo.self).identity else {
                    return .problem(.grokLogin)
                }
                do {
                    let limits = try await rpc.request("_x.ai/billing", id: 3, as: BillingResponse.self).limits()
                    // Check again before accepting a response from an account
                    // that may have switched while the request was in flight.
                    guard let current = try await rpc.request("_x.ai/auth/info", id: 4, as: AuthInfo.self).identity else {
                        return .problem(.grokLogin)
                    }
                    guard current == identity else { return .unavailableForAccount(current, discardPrevious: true) }
                    return .limits(limits, identity: identity)
                } catch {
                    return Self.failure(error, identity: identity)
                }
            }
        } catch {
            return Self.failure(error, identity: nil)
        }
    }

    private static func failure(_ error: any Error, identity: ProviderIdentity?) -> FetchResult {
        switch error {
        case GrokError.incompatible: .problem(.grokResponse)
        case GrokError.rpc(let code, _) where code == -32601 || code == -32602: .problem(.grokResponse)
        case GrokError.rpc(_, let message) where message.lowercased().contains("authentication required"): .problem(.grokLogin)
        default: identity.map { .unavailableForAccount($0) } ?? .unavailable
        }
    }
}

private nonisolated struct Initialization: Decodable, Sendable { let protocolVersion: Int }

nonisolated extension Problem {
    static let grokNotFound = Problem(heading: "Grok not found",
        message: "Install Grok with `curl -fsSL https://x.ai/cli/install.sh | bash`, then run `grok login` in Terminal.",
        link: ProblemLink(title: "Install Grok", url: URL(string: "https://x.ai/cli")!))
    static let grokLogin = Problem(heading: "Sign in to Grok",
        message: "Run `grok login` in Terminal. Pacemark needs Grok's own login.", link: nil)
    static let grokResponse = Problem(heading: "Can't read Grok limits",
        message: "Grok returned a response Pacemark can't read. Update Grok, or check for a newer Pacemark release.",
        link: ProblemLink(title: "Pacemark releases", url: URL(string: "https://github.com/chris-metz/pacemark/releases")!))
}
