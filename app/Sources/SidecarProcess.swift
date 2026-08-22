import Foundation

// One NDJSON progress event from a worker script or the transcriber.
struct SidecarEvent: Decodable {
    let type: String
    let stage: String?
    let percent: Int?
    let message: String?
    let text: String?
    let output: String?
    let subtitles: String?
    let attempt: Int?
    let tool: String?
}

enum SidecarError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

// Captured output of a plain (non-NDJSON) subprocess run.
struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

// Runs a subprocess that emits NDJSON on stdout. Forwards each event,
// returns the final "done" event, and throws on "error" events or a
// non-zero exit.
enum Sidecar {
    // The one plain-process primitive. Spawns, captures both streams in
    // full, and returns when the process exits. Callers decide what counts
    // as failure. `started` hands out the Process so callers can cancel it.
    static func runProcess(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        cwd: URL? = nil,
        started: (@Sendable (Process) -> Void)? = nil
    ) async -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0] = $1 }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let state = CaptureState()
        stdout.fileHandleForReading.readabilityHandler = { state.appendOut($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { state.appendErr($0.availableData) }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if let rest = try? stdout.fileHandleForReading.readToEnd() { state.appendOut(rest) }
                if let rest = try? stderr.fileHandleForReading.readToEnd() { state.appendErr(rest) }
                let (out, err) = state.snapshot()
                continuation.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: out, stderr: err))
            }
            do {
                try process.run()
                started?(process)
            } catch {
                continuation.resume(returning: ProcessResult(status: -1, stdout: "", stderr: String(describing: error)))
            }
        }
    }

    @discardableResult
    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        cwd: URL? = nil,
        debug: DebugLog? = nil,
        onEvent: @escaping (SidecarEvent) -> Void
    ) async throws -> SidecarEvent {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0] = $1 }
        process.environment = env

        debug?.log(.command, "\(executable.path) \(arguments.joined(separator: " "))")

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            let state = SidecarState()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in state.appendAndSplit(data) {
                    guard let event = try? JSONDecoder().decode(SidecarEvent.self, from: Data(line.utf8)) else {
                        debug?.log(.stdout, line)
                        continue
                    }
                    debug?.log(event.type == "error" ? .error : .stdout, line)
                    state.record(event)
                    DispatchQueue.main.async { onEvent(event) }
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                state.appendStderr(text)
                debug?.log(.stderr, text)
            }

            process.terminationHandler = { proc in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                // Drain anything still buffered.
                if let rest = try? stdout.fileHandleForReading.readToEnd(), !rest.isEmpty {
                    for line in state.appendAndSplit(rest) {
                        if let event = try? JSONDecoder().decode(SidecarEvent.self, from: Data(line.utf8)) {
                            state.record(event)
                        }
                    }
                }
                let (done, errorMessage, stderrTail) = state.snapshot()
                if let message = errorMessage {
                    continuation.resume(throwing: SidecarError.failed(message))
                } else if proc.terminationStatus != 0 {
                    continuation.resume(throwing: SidecarError.failed(stderrTail.isEmpty ? "a step failed unexpectedly" : stderrTail))
                } else if let done {
                    continuation.resume(returning: done)
                } else {
                    continuation.resume(throwing: SidecarError.failed("a step finished without reporting a result"))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// Accumulates a plain run's streams, guarded by a lock.
private final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }

    func snapshot() -> (String, String) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

// Mutable state shared between pipe handlers, guarded by a lock.
private final class SidecarState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var stderrTail = ""
    private var doneEvent: SidecarEvent?
    private var errorMessage: String?

    func appendAndSplit(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer += String(decoding: data, as: UTF8.self)
        var lines = buffer.components(separatedBy: "\n")
        buffer = lines.removeLast()
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func appendStderr(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        stderrTail = String((stderrTail + text).suffix(2000))
    }

    func record(_ event: SidecarEvent) {
        lock.lock(); defer { lock.unlock() }
        if event.type == "done" { doneEvent = event }
        if event.type == "error" { errorMessage = event.message ?? "unknown error" }
    }

    func snapshot() -> (SidecarEvent?, String?, String) {
        lock.lock(); defer { lock.unlock() }
        return (doneEvent, errorMessage, stderrTail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
