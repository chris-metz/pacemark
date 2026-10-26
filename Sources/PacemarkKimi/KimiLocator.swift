import Foundation

nonisolated enum KimiLocator {
    static func environment(homeDirectory: URL, binary: URL? = nil) -> [String: String] {
        // `kimi` is a Node script: the unresolved binary's directory usually
        // holds `node` too, e.g. with mise. Never inherit API-key, base-URL
        // or home overrides; no telemetry for Pacemark's short-lived servers.
        let prefix = binary.map { $0.deletingLastPathComponent().path + ":" } ?? ""
        return ["HOME": homeDirectory.path, "USER": NSUserName(), "KIMI_DISABLE_TELEMETRY": "1",
                "PATH": prefix + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    static func locate(homeDirectory: URL) async -> URL? {
        let candidates = [homeDirectory.appending(path: ".local/bin/kimi"),
                          URL(filePath: "/opt/homebrew/bin/kimi"), URL(filePath: "/usr/local/bin/kimi")]
        if let found = candidates.first(where: executableFile) { return found }
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        guard let output = try? await KimiProcess.output(executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", "command -v kimi"], directory: homeDirectory,
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
