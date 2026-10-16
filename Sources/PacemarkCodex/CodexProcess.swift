import Foundation
import Synchronization

nonisolated enum CodexError: Error {
    case unavailable
    case incompatible
    case rpc(code: Int, message: String)
}

/// One bounded, cancellable child process. Both the shell lookup and the
/// app-server use it. No account data or subprocess stderr is logged.
nonisolated final class CodexProcess: Sendable {
    private let process: Process
    private let input: FileHandle
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
        let stdin = Pipe()
        let stdout = Pipe()
        input = stdin.fileHandleForWriting
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        output = stdout.fileHandleForReading
        process.standardInput = stdin
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
                        continuation.finish(throwing: CodexError.incompatible)
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

    func send(_ text: String) throws {
        try input.write(contentsOf: Data((text + "\n").utf8))
    }

    func interrupt() {
        // Foundation starts a new process group, so descendants stop too.
        kill(-process.processIdentifier, SIGKILL)
        continuation.finish(throwing: CodexError.unavailable)
    }

    func close() async {
        try? input.close()
        kill(-process.processIdentifier, SIGTERM)
        try? await Task.sleep(for: .milliseconds(50))
        kill(-process.processIdentifier, SIGKILL)
        for await _ in exit {}
        output.readabilityHandler = nil
        try? output.close()
        continuation.finish()
    }

    /// Completes only after the child is reaped, including on cancellation
    /// and timeout. The timeout bounds the whole exchange, not each line.
    func perform<Value: Sendable>(timeout: Duration, _ operation: () async throws -> Value) async throws -> Value {
        let watchdog = Task { [self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            interrupt()
        }
        let result: Result<Value, any Error> = await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                return .success(try await operation())
            } catch { return .failure(error) }
        } onCancel: { self.interrupt() }
        watchdog.cancel()
        await watchdog.value
        // Cleanup must finish even when the caller has been cancelled.
        await Task.detached { await self.close() }.value
        return try result.get()
    }

    static func output(executable: URL, arguments: [String], directory: URL,
                       environment: [String: String], timeout: Duration) async throws -> String {
        let child = try CodexProcess(executable: executable, arguments: arguments, directory: directory, environment: environment)
        return try await child.perform(timeout: timeout) {
            var output = Data()
            for try await line in child.lines {
                output.append(line)
                output.append(10)
            }
            for await _ in child.exit {}
            guard child.process.terminationStatus == 0 else { throw CodexError.unavailable }
            return String(decoding: output, as: UTF8.self)
        }
    }
}

/// JSON-RPC uses one line per message and omits the jsonrpc field.
nonisolated struct CodexExchange {
    let child: CodexProcess
    var iterator: AsyncThrowingStream<Data, any Error>.Iterator

    init(_ child: CodexProcess) {
        self.child = child
        iterator = child.lines.makeAsyncIterator()
    }

    mutating func request<Response: Decodable & Sendable>(
        _ method: String, id: Int, params: String = "{}", as: Response.Type
    ) async throws -> Response {
        try child.send(#"{"id":\#(id),"method":"\#(method)","params":\#(params)}"#)
        while let line = try await iterator.next() {
            if line.isEmpty { continue }
            guard let header = try? JSONDecoder().decode(Header.self, from: line) else { throw CodexError.incompatible }
            if header.method != nil {
                // Pacemark never initiates a thread or answers server requests.
                if header.id != nil { throw CodexError.incompatible }
                continue
            }
            guard header.id == id else { throw CodexError.incompatible }
            if let error = header.error { throw CodexError.rpc(code: error.code, message: error.message) }
            guard let envelope = try? JSONDecoder().decode(Envelope<Response>.self, from: line) else {
                throw CodexError.incompatible
            }
            return envelope.result
        }
        throw CodexError.unavailable
    }

    private struct Header: Decodable {
        var id: Int?
        var method: String?
        var error: RPCError?
    }
    private struct RPCError: Decodable { var code: Int; var message: String }
    private struct Envelope<Response: Decodable>: Decodable { var result: Response }
}
