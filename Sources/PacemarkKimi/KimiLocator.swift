import Foundation

nonisolated enum KimiLocator {
    static func environment(homeDirectory: URL, binary: URL? = nil, node: URL? = nil) -> [String: String] {
        // `kimi` is a Node script. With npm under mise, the unresolved
        // binary's directory holds `node` too; a pnpm shim takes `node` from
        // `PATH`, so the login shell's `node` comes next. Never inherit
        // API-key, base-URL or home overrides; no telemetry for Pacemark's
        // short-lived servers.
        var directories = binary.map { [$0.deletingLastPathComponent().path] } ?? []
        if let node = node?.deletingLastPathComponent().path, !directories.contains(node) { directories.append(node) }
        let prefix = directories.map { $0 + ":" }.joined()
        return ["HOME": homeDirectory.path, "USER": NSUserName(), "KIMI_DISABLE_TELEMETRY": "1",
                "PATH": prefix + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    static func locate(homeDirectory: URL) async -> (binary: URL, node: URL?)? {
        let candidates = [homeDirectory.appending(path: ".local/bin/kimi"),
                          URL(filePath: "/opt/homebrew/bin/kimi"), URL(filePath: "/usr/local/bin/kimi")]
        if let found = candidates.first(where: executableFile) { return (found, nil) }
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        // `kimi` last: the exit status says whether it was found, with or
        // without `node`.
        guard let output = try? await KimiProcess.output(executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", "command -v node; command -v kimi"], directory: homeDirectory,
            environment: environment(homeDirectory: homeDirectory), timeout: .seconds(5)) else { return nil }
        return installation(in: output)
    }

    /// Reads the login shell's answer. Startup files may print anything
    /// before it.
    static func installation(in output: String) -> (binary: URL, node: URL?)? {
        let paths = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }.map { URL(filePath: $0) }.filter(executableFile)
        guard let binary = paths.last(where: { $0.lastPathComponent == "kimi" }) else { return nil }
        return (binary, paths.last { $0.lastPathComponent == "node" })
    }

    private static func executableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
