import Foundation

/// Owns single-document import work independently of SwiftUI presentation.
/// Operation IDs prevent a cancelled or superseded conversion from publishing
/// a stale preview or completion into a different document session.
@MainActor
final class DocumentImportCoordinator: ObservableObject {
    typealias Loader = (URL) async throws -> DocumentImportDraft
    typealias Saver = (
        DocumentImportDraft,
        [UUID: DocumentTrackedChangeDecision],
        URL
    ) async throws -> DocumentImportSaveResult

    @Published var draft: DocumentImportDraft?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private let loader: Loader
    private let saver: Saver
    private let operationController = CancellableOperationController()

    init(
        loader: @escaping Loader = { url in
            let worker = Task.detached(priority: .userInitiated) {
                try DocumentImportService.load(from: url)
            }
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        },
        saver: @escaping Saver = { draft, decisions, outputURL in
            let worker = Task.detached(priority: .userInitiated) {
                try DocumentImportService.save(
                    draft,
                    decisions: decisions,
                    to: outputURL
                )
            }
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        }
    ) {
        self.loader = loader
        self.saver = saver
    }

    func load(from url: URL) {
        begin { [loader] in try await loader(url) } completion: { [weak self] draft in
            self?.draft = draft
        }
    }

    func save(
        _ draft: DocumentImportDraft,
        decisions: [UUID: DocumentTrackedChangeDecision],
        to outputURL: URL,
        completion: @escaping (DocumentImportSaveResult) -> Void
    ) {
        self.draft = nil
        begin { [saver] in
            try await saver(draft, decisions, outputURL)
        } completion: { result in
            completion(result)
        }
    }

    func clearDraft() {
        draft = nil
    }

    func cancel() {
        operationController.cancel()
        isRunning = false
    }

    private func begin<Value: Sendable>(
        operation: @escaping () async throws -> Value,
        completion: @escaping (Value) -> Void
    ) {
        cancel()
        errorMessage = nil
        isRunning = true
        operationController.start { [weak self] token in
            do {
                let value = try await operation()
                guard let self, self.operationController.accepts(token) else { return }
                completion(value)
                self.finish(token)
            } catch is CancellationError {
                self?.finish(token)
            } catch {
                guard let self, self.operationController.accepts(token) else { return }
                self.errorMessage = error.localizedDescription
                self.finish(token)
            }
        }
    }

    private func finish(_ token: CancellableOperationController.Token) {
        guard operationController.finish(token) else { return }
        isRunning = false
    }
}
