import Foundation

enum BackendError: Error, LocalizedError {
    case executableNotFound
    case processLaunchFailed(String)
    case invalidResponse(String)
    case backendReportedError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not locate the bundled processing engine. See ClassicsPDFAssistant/README.md."
        case .processLaunchFailed(let message):
            return "Failed to launch the processing engine: \(message)"
        case .invalidResponse(let raw):
            return "The processing engine returned an unexpected response:\n\(raw)"
        case .backendReportedError(let message):
            return message
        case .cancelled:
            return "Processing was cancelled."
        }
    }
}

/// Wraps the `pdf_backend_cli` subprocess: writes one JSON request to stdin,
/// streams NDJSON progress events from stderr, and decodes one final JSON
/// response from stdout. One instance handles one command invocation; the
/// call site creates a fresh instance (or reuses this actor sequentially)
/// per command. See docs/JSON_PROTOCOL.md for the exact wire contract.
actor BackendService {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var currentProcess: Process?

    init() {
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func run<Request: Encodable, Response: BackendResponseEnvelope>(
        command: String,
        request: Request,
        onProgress: @escaping @Sendable (ProgressEvent) -> Void
    ) async throws -> Response {
        guard let invocation = resolveInvocation() else {
            throw BackendError.executableNotFound
        }

        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.argumentsPrefix + [command, "--request", "-"]

        var environment = ProcessInfo.processInfo.environment
        if let tessdata = resolveTessdataDirectory() {
            environment["TESSDATA_PREFIX"] = tessdata.path
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let requestData = try encoder.encode(request)
        let decoderForProgress = decoder

        var stdoutData = Data()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutData.append(chunk) }
        }

        var stderrBuffer = Data()
        let newline = Data([0x0A])
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
            while let range = stderrBuffer.range(of: newline) {
                let lineData = stderrBuffer.subdata(in: stderrBuffer.startIndex..<range.lowerBound)
                stderrBuffer.removeSubrange(stderrBuffer.startIndex..<range.upperBound)
                if !lineData.isEmpty, let event = try? decoderForProgress.decode(ProgressEvent.self, from: lineData) {
                    onProgress(event)
                }
            }
        }

        do {
            try process.run()
        } catch {
            throw BackendError.processLaunchFailed(error.localizedDescription)
        }
        currentProcess = process

        // Write stdin off the actor's execution context: request payloads
        // (a `finalize` call's corrected OCR words, especially) can exceed
        // the pipe's kernel buffer, and the child only starts draining
        // stdin after it starts running — writing synchronously here, with
        // the child not yet guaranteed to be reading, risks a classic pipe
        // deadlock. The stdout/stderr readability handlers are already
        // installed above, so the child is never blocked writing its own
        // output while this write is in flight.
        let writeHandle = stdinPipe.fileHandleForWriting
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                writeHandle.write(requestData)
                try? writeHandle.close()
                continuation.resume()
            }
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        currentProcess = nil

        if process.terminationReason == .uncaughtSignal {
            throw BackendError.cancelled
        }

        guard let response = try? decoder.decode(Response.self, from: stdoutData) else {
            let raw = String(data: stdoutData, encoding: .utf8) ?? "<\(stdoutData.count) bytes, not UTF-8>"
            throw BackendError.invalidResponse(raw)
        }
        if response.status == "error" {
            throw BackendError.backendReportedError(response.error ?? "Unknown backend error")
        }
        return response
    }

    /// Sends SIGTERM to the in-flight subprocess, if any. The backend cleans
    /// up its own per-document temp directory on interruption.
    func cancelCurrent() {
        currentProcess?.terminate()
    }

    private func resolveInvocation() -> (executable: URL, argumentsPrefix: [String])? {
        if let bundled = BackendLocator.bundledExecutable() {
            return (bundled, [])
        }
        if let dev = BackendLocator.devInvocation() {
            return (dev.executable, dev.argumentsPrefix)
        }
        return nil
    }

    private func resolveTessdataDirectory() -> URL? {
        BackendLocator.bundledTessdataDirectory() ?? BackendLocator.devTessdataDirectory()
    }
}
