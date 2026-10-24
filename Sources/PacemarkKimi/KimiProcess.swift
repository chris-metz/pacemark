import Foundation
import Synchronization

nonisolated enum KimiError: Error {
    case unavailable
    case incompatible
    case login
}

/// One bounded, cancellable child process: the shell lookup or the local
/// server. No account data, server token or subprocess stderr is logged.
nonisolated final class KimiProcess: Sendable {
    private let process: Process
    private let output: FileHandle
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    let lines: AsyncThrowingStream<Data, any Error>
    private let exit: AsyncStream<Void>
    private let buffer = Mutex((data: Data(), count: 0))

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String]) throws {
        let process = Process()
        self.process = process
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let stdout = Pipe()
        output = stdout.fileHandleForReading
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let (lines, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        self.lines = lines
        self.continuation = continuation
        let (exit, exited) = AsyncStream.makeStream(of: Void.self)
        self.exit = exit
        process.terminationHandler = { _ in exited.finish() }
        try process.run()
        output.readabilityHandler = { [self] handle in
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = read(handle.fileDescriptor, &bytes, bytes.count)
            if count > 0 {
                buffer.withLock { state in
                    state.count += count
                    guard state.count <= 2 * 1024 * 1024 else {
                        continuation.finish(throwing: KimiError.incompatible)
                        return
                    }
                    state.data.append(contentsOf: bytes[..<count])
                    while let newline = state.data.firstIndex(of: 10) {
                        continuation.yield(Data(state.data[..<newline]))
                        state.data.removeSubrange(...newline)
                    }
                }
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                handle.readabilityHandler = nil
                buffer.withLock { state in
                    if !state.data.isEmpty { continuation.yield(state.data) }
                    state.data.removeAll()
                }
                continuation.finish()
            }
        }
    }

    /// Reads stdout until `kimi web` reports where it listens. A child that
    /// exits first has an output Pacemark can't read.
    func readyServer() async throws -> (origin: URL, token: String) {
        for try await line in lines {
            let text = String(decoding: line, as: UTF8.self)
            guard text.hasPrefix("Kimi server: ") else { continue }
            guard let url = URLComponents(string: String(text.dropFirst(13)).trimmingCharacters(in: .whitespaces)),
                  url.scheme == "http", let host = url.host, let port = url.port,
                  let token = url.fragment?.split(separator: "=", maxSplits: 1),
                  token.count == 2, token[0] == "token", !token[1].isEmpty else { throw KimiError.incompatible }
            var origin = URLComponents()
            origin.scheme = "http"
            origin.host = host
            origin.port = port
            guard let originURL = origin.url else { throw KimiError.incompatible }
            return (originURL, String(token[1]))
        }
        throw KimiError.incompatible
    }

    /// Stops the server gracefully, so it can release its instance
    /// registration and flush its indexes. Foundation starts a new process
    /// group, so descendants stop too.
    func interrupt() {
        kill(-process.processIdentifier, SIGTERM)
        continuation.finish(throwing: KimiError.unavailable)
    }

    func close() async {
        kill(-process.processIdentifier, SIGTERM)
        // Only a child that ignores SIGTERM is killed.
        let pid = process.processIdentifier
        let killer = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            kill(-pid, SIGKILL)
        }
        for await _ in exit {}
        killer.cancel()
        output.readabilityHandler = nil
        try? output.close()
        continuation.finish()
    }

    /// Completes only after the child is reaped, including on cancellation
    /// and timeout. The timeout bounds the whole exchange, not each step.
    func perform<Value: Sendable>(timeout: Duration,
                                  _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        // A separate task, so a timeout also cancels a request in flight.
        let work = Task { try await operation() }
        let watchdog = Task { [self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            interrupt()
            work.cancel()
        }
        let result = await withTaskCancellationHandler {
            await work.result
        } onCancel: {
            self.interrupt()
            work.cancel()
        }
        watchdog.cancel()
        await watchdog.value
        // Cleanup must finish even when the caller has been cancelled.
        await Task.detached { await self.close() }.value
        return try result.get()
    }

    static func output(executable: URL, arguments: [String], directory: URL,
                       environment: [String: String], timeout: Duration) async throws -> String {
        let child = try KimiProcess(executable: executable, arguments: arguments, directory: directory, environment: environment)
        return try await child.perform(timeout: timeout) {
            var output = Data()
            for try await line in child.lines {
                output.append(line)
                output.append(10)
            }
            for await _ in child.exit {}
            guard child.process.terminationStatus == 0 else { throw KimiError.unavailable }
            return String(decoding: output, as: UTF8.self)
        }
    }
}
