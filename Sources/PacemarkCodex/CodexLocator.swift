import Foundation

nonisolated enum CodexLocator {
    static func environment(homeDirectory: URL, binary: URL? = nil) -> [String: String] {
        // Preserve Codex's default persistent login; never inherit API-key
        // overrides or this process's agent credentials.
        let prefix = binary.map { $0.deletingLastPathComponent().path + ":" } ?? ""
        return ["HOME": homeDirectory.path, "USER": NSUserName(),
                "PATH": prefix + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    static func locate(homeDirectory: URL) async -> URL? {
        let candidates = [homeDirectory.appending(path: ".local/bin/codex"),
                          URL(filePath: "/opt/homebrew/bin/codex"), URL(filePath: "/usr/local/bin/codex")]
        if let found = candidates.first(where: executableFile) { return found }
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        guard let output = try? await CodexProcess.output(executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", "command -v codex"], directory: homeDirectory,
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
