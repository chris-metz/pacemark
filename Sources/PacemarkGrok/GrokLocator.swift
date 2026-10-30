import Foundation

nonisolated enum GrokLocator {
    static func environment(homeDirectory: URL, binary: URL? = nil) -> [String: String] {
        // Keep Grok's own login: never inherit an API key, a home, config or
        // endpoint override. No telemetry for Pacemark's short-lived agents.
        let prefix = binary.map { $0.deletingLastPathComponent().path + ":" } ?? ""
        return ["HOME": homeDirectory.path, "USER": NSUserName(), "GROK_TELEMETRY_ENABLED": "0",
                "PATH": prefix + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    static func locate(homeDirectory: URL) async -> URL? {
        // The official installer uses ~/.grok/bin.
        let candidates = [homeDirectory.appending(path: ".grok/bin/grok"), homeDirectory.appending(path: ".local/bin/grok"),
                          URL(filePath: "/opt/homebrew/bin/grok"), URL(filePath: "/usr/local/bin/grok")]
        if let found = candidates.first(where: executableFile) { return found }
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        guard let output = try? await GrokProcess.output(executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", "command -v grok"], directory: homeDirectory,
            environment: environment(homeDirectory: homeDirectory), timeout: .seconds(5)) else { return nil }
        return output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }.map { URL(filePath: $0) }.last(where: executableFile)
    }

    private static func executableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
