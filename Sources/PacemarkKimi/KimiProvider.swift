import Foundation
import PacemarkKit

/// One authorized GET to the local server: its status code and body.
typealias KimiTransport = @Sendable (_ url: URL, _ token: String) async throws -> (status: Int, body: Data)

/// Reads limits through a short-lived `kimi web` server using Kimi Code's
/// own login. It never starts a model turn or touches the account's
/// credentials; it only uses the token its own server prints for it.
public nonisolated struct KimiProvider: Provider {
    public let id = "kimi"
    public let name = "Kimi"
    /// `nil`: located anew for each query.
    private let installation: KimiInstallation?
    private let homeDirectory: URL
    private let timeout: Duration
    private let transport: KimiTransport

    public init() {
        installation = nil
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        timeout = .seconds(30)
        transport = Self.urlSession
    }

    init(executable: URL, node: URL? = nil, homeDirectory: URL, timeout: Duration, transport: @escaping KimiTransport) {
        installation = KimiInstallation(binary: executable, node: node)
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.transport = transport
    }

    @concurrent public func fetch() async -> FetchResult {
        do {
            let located = if let installation { installation } else { await KimiLocator.locate(homeDirectory: homeDirectory) }
            guard let located, FileManager.default.isExecutableFile(atPath: located.binary.path) else {
                return .problem(.kimiNotFound)
            }
            // Port 0: the server picks a free port and reports it.
            let child = try KimiProcess(executable: located.binary,
                arguments: ["web", "--no-open", "--port", "0", "--log-level", "warn"], directory: homeDirectory,
                environment: KimiLocator.environment(homeDirectory: homeDirectory, installation: located))
            return try await child.perform(timeout: timeout) { [transport] in
                let (origin, token) = try await child.readyServer()
                let server = KimiServer(origin: origin, token: token, transport: transport)
                let identity = try await server.identity()
                do {
                    let limits = try await server.limits()
                    // Check again before accepting a response from an account
                    // that may have switched while the request was in flight.
                    let current = try await server.identity()
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
        case KimiError.login: .problem(.kimiLogin)
        case KimiError.incompatible: .problem(.kimiResponse)
        default: identity.map { .unavailableForAccount($0) } ?? .unavailable
        }
    }

    /// Ephemeral, so neither the server token nor account data is cached.
    private static let session = URLSession(configuration: .ephemeral)

    private static let urlSession: KimiTransport = { url, token in
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (body, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, body)
    }
}

/// The routes Pacemark reads on one running `kimi web` server.
private nonisolated struct KimiServer {
    let origin: URL
    let token: String
    let transport: KimiTransport

    func identity() async throws -> ProviderIdentity {
        guard let info = try await get("userinfo").userInfo else { throw KimiError.incompatible }
        return ProviderIdentity(email: info.email, accountID: info.userId)
    }

    func limits() async throws -> [Limit] {
        guard let windows = try await get("usage").quota?.usages else { throw KimiError.incompatible }
        return try windows.limits()
    }

    private func get(_ route: String) async throws -> AccountResponse {
        let url = origin.appending(path: "api/v1/oauth/\(route)")
            .appending(queryItems: [URLQueryItem(name: "provider", value: "managed:kimi-code")])
        let (status, body) = try await transport(url, token)
        guard status == 200 else { throw (500..<600).contains(status) ? KimiError.unavailable : KimiError.incompatible }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { throw KimiError.incompatible }
        guard envelope.code == 0 else { throw KimiError.unavailable }
        guard let response = envelope.data else { throw KimiError.incompatible }
        switch response.kind {
        case "ok": return response
        case "error": throw response.isLoginError ? KimiError.login : KimiError.unavailable
        default: throw KimiError.incompatible
        }
    }
}

nonisolated extension Problem {
    static let kimiNotFound = Problem(heading: "Kimi Code not found",
        message: "Install Kimi Code, then run `kimi login` in Terminal.",
        link: ProblemLink(title: "Install Kimi Code", url: URL(string: "https://moonshotai.github.io/kimi-code/")!))
    static let kimiLogin = Problem(heading: "Sign in to Kimi Code",
        message: "Run `kimi login` in Terminal. Pacemark needs Kimi Code's own login.", link: nil)
    static let kimiResponse = Problem(heading: "Can't read Kimi limits",
        message: "Kimi Code returned a response Pacemark can't read. Update Kimi Code, or check for a newer Pacemark release.",
        link: ProblemLink(title: "Pacemark releases", url: URL(string: "https://github.com/chris-metz/pacemark/releases")!))
}
