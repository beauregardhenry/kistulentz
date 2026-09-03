import Foundation

actor BeneparService {
    static let shared = BeneparService()

    private let rootURL: URL
    private var worker: BeneparWorkerProcess?
    private var installationPath: String?
    private var isAnalyzing = false

    init(rootURL: URL = BeneparLanguagePackLocator.defaultRootURL()) {
        self.rootURL = rootURL
    }

    func analyzeIfAvailable(
        text: String,
        maximumSentences: Int,
        includeIssues: Bool,
        waitForAvailability: Bool = false
    ) async -> BeneparAnalysis? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if waitForAvailability {
            let deadline = Date().addingTimeInterval(150)
            while isAnalyzing, Date() < deadline {
                guard !Task.isCancelled else { return nil }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard !isAnalyzing, !Task.isCancelled else { return nil }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            return try await analyze(
                text: text,
                maximumSentences: maximumSentences,
                includeIssues: includeIssues
            )
        } catch {
            if error is BeneparLanguagePackError {
                worker?.close()
                worker = nil
                installationPath = nil
            }
            return nil
        }
    }

    func analyze(
        text: String,
        maximumSentences: Int,
        includeIssues: Bool
    ) async throws -> BeneparAnalysis {
        guard let installation = try BeneparLanguagePackLocator.locate(at: rootURL) else {
            throw BeneparLanguagePackError.invalidManifest("the pack is not installed")
        }
        let activeWorker = try makeWorkerIfNeeded(for: installation)
        let request = BeneparWorkerRequest(
            id: UUID().uuidString,
            command: "analyze",
            text: text,
            maximumSentences: max(1, min(maximumSentences, 400)),
            includeIssues: includeIssues
        )
        let requestData = try JSONEncoder().encode(request)
        let responseData: Data
        do {
            responseData = try await activeWorker.request(
                requestData,
                id: request.id,
                timeout: includeIssues ? 120 : 300
            )
        } catch {
            activeWorker.close()
            worker = nil
            installationPath = nil
            throw error
        }
        let response = try JSONDecoder().decode(BeneparWorkerResponse.self, from: responseData)
        guard response.ok else {
            throw BeneparLanguagePackError.workerRejected(response.error ?? "Unknown worker error")
        }
        guard let metrics = response.metrics else {
            throw BeneparLanguagePackError.workerRejected("The worker returned no structural metrics")
        }
        let issues = (response.issues ?? []).compactMap { $0.writingIssue(in: text) }
        return BeneparAnalysis(metrics: metrics, issues: issues)
    }

    func destinkIfAvailable(
        text: String,
        maximumSentences: Int,
        waitForAvailability: Bool = true
    ) async -> BeneparDestinkAnalysis? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if waitForAvailability {
            let deadline = Date().addingTimeInterval(150)
            while isAnalyzing, Date() < deadline {
                guard !Task.isCancelled else { return nil }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard !isAnalyzing, !Task.isCancelled else { return nil }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            return try await destink(text: text, maximumSentences: maximumSentences)
        } catch {
            if error is BeneparLanguagePackError {
                worker?.close()
                worker = nil
                installationPath = nil
            }
            return nil
        }
    }

    func destink(text: String, maximumSentences: Int) async throws -> BeneparDestinkAnalysis {
        guard let installation = try BeneparLanguagePackLocator.locate(at: rootURL) else {
            throw BeneparLanguagePackError.invalidManifest("the pack is not installed")
        }
        let activeWorker = try makeWorkerIfNeeded(for: installation)
        let request = BeneparWorkerRequest(
            id: UUID().uuidString,
            command: "destink",
            text: text,
            maximumSentences: max(1, min(maximumSentences, 400)),
            includeIssues: false
        )
        let requestData = try JSONEncoder().encode(request)
        let responseData: Data
        do {
            responseData = try await activeWorker.request(requestData, id: request.id, timeout: 180)
        } catch {
            activeWorker.close()
            worker = nil
            installationPath = nil
            throw error
        }
        let response = try JSONDecoder().decode(BeneparWorkerResponse.self, from: responseData)
        guard response.ok else {
            throw BeneparLanguagePackError.workerRejected(response.error ?? "Unknown worker error")
        }
        return BeneparDestinkAnalysis(findings: (response.destinkFindings ?? []).compactMap {
            $0.finding(in: text)
        })
    }

    func reset() {
        worker?.close()
        worker = nil
        installationPath = nil
        isAnalyzing = false
    }

    private func makeWorkerIfNeeded(
        for installation: BeneparLanguagePackInstallation
    ) throws -> BeneparWorkerProcess {
        if let worker,
           installationPath == installation.rootURL.path,
           worker.isRunning {
            return worker
        }
        worker?.close()
        guard let workerURL = Self.workerURL() else {
            throw BeneparLanguagePackError.workerUnavailable
        }
        let next = try BeneparWorkerProcess(installation: installation, workerURL: workerURL)
        worker = next
        installationPath = installation.rootURL.path
        return next
    }

    nonisolated static func workerURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        let bundled = bundle.resourceURL?
            .appendingPathComponent("LanguagePacks", isDirectory: true)
            .appendingPathComponent("Benepar", isDirectory: true)
            .appendingPathComponent("benepar_worker.py")
        if let bundled, fileManager.fileExists(atPath: bundled.path) { return bundled }

        let development = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("LanguagePacks", isDirectory: true)
            .appendingPathComponent("Benepar", isDirectory: true)
            .appendingPathComponent("benepar_worker.py")
        return fileManager.fileExists(atPath: development.path) ? development : nil
    }
}

private struct BeneparWorkerRequest: Encodable {
    let id: String
    let command: String
    let text: String
    let maximumSentences: Int
    let includeIssues: Bool
}

private struct BeneparWorkerEnvelope: Decodable {
    let id: String?
    let ok: Bool
    let error: String?
}

private final class BeneparWorkerProcess: @unchecked Sendable {
    private let process: Process
    private let input: Pipe
    private let output: Pipe
    private let errors: Pipe
    private let stateQueue = DispatchQueue(label: "com.beauhenry.kistulentz.benepar-worker")
    private var outputBuffer = Data()
    private var recentErrors = ""
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var closed = false

    var isRunning: Bool {
        stateQueue.sync { process.isRunning && !closed }
    }

    init(
        installation: BeneparLanguagePackInstallation,
        workerURL: URL
    ) throws {
        process = Process()
        input = Pipe()
        output = Pipe()
        errors = Pipe()

        process.executableURL = installation.pythonURL
        process.arguments = [workerURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["KISTULENTZ_BENEPAR_MODEL"] = installation.modelURL.path
        environment["NLTK_DATA"] = installation.rootURL.appendingPathComponent("nltk_data").path
        environment["HF_HOME"] = installation.rootURL.appendingPathComponent("cache", isDirectory: true).path
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["OMP_NUM_THREADS"] = "2"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consumeOutput(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consumeError(data)
        }
        process.terminationHandler = { [weak self] process in
            self?.workerTerminated(status: process.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw BeneparLanguagePackError.workerStopped(error.localizedDescription)
        }
    }

    func request(_ data: Data, id: String, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.closed, self.process.isRunning else {
                    continuation.resume(throwing: BeneparLanguagePackError.workerStopped("The local process is not running."))
                    return
                }
                self.pending[id] = continuation
                do {
                    var line = data
                    line.append(0x0A)
                    try self.input.fileHandleForWriting.write(contentsOf: line)
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: BeneparLanguagePackError.workerStopped(error.localizedDescription))
                    return
                }
                self.stateQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let continuation = self?.pending.removeValue(forKey: id) else { return }
                    continuation.resume(throwing: BeneparLanguagePackError.workerTimedOut)
                }
            }
        }
    }

    func close() {
        let continuations: [CheckedContinuation<Data, Error>] = stateQueue.sync {
            guard !closed else { return [] }
            closed = true
            let values = Array(pending.values)
            pending.removeAll()
            return values
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuations.forEach {
            $0.resume(throwing: BeneparLanguagePackError.workerStopped("The local process was reset."))
        }
    }

    private func consumeOutput(_ data: Data) {
        stateQueue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.outputBuffer.append(data)
            while let newline = self.outputBuffer.firstIndex(of: 0x0A) {
                let line = Data(self.outputBuffer[..<newline])
                self.outputBuffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let envelope = try? JSONDecoder().decode(BeneparWorkerEnvelope.self, from: line),
                      let id = envelope.id,
                      let continuation = self.pending.removeValue(forKey: id) else { continue }
                if envelope.ok {
                    continuation.resume(returning: line)
                } else {
                    continuation.resume(
                        throwing: BeneparLanguagePackError.workerRejected(envelope.error ?? "Unknown worker error")
                    )
                }
            }
        }
    }

    private func consumeError(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.recentErrors.append(text)
            if self.recentErrors.count > 4_000 {
                self.recentErrors = String(self.recentErrors.suffix(4_000))
            }
        }
    }

    private func workerTerminated(status: Int32) {
        let result: (continuations: [CheckedContinuation<Data, Error>], detail: String) = stateQueue.sync {
            guard !closed else { return ([], "") }
            closed = true
            let values = Array(pending.values)
            pending.removeAll()
            let detail = recentErrors.trimmingCharacters(in: .whitespacesAndNewlines)
            return (values, detail)
        }
        let message = result.detail.isEmpty
            ? "The worker exited with status \(status)."
            : String(result.detail.suffix(800))
        result.continuations.forEach {
            $0.resume(throwing: BeneparLanguagePackError.workerStopped(message))
        }
    }
}
