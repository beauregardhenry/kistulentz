import Foundation

/// Gives long-running UI work one consistent cancellation and stale-result boundary.
/// Starting a new operation cancels the previous task. Callbacks may publish state only while
/// their token remains current; finishing or cancelling invalidates it immediately.
@MainActor
final class CancellableOperationController {
    struct Token: Hashable, Sendable {
        fileprivate let id: UUID
    }

    private var task: Task<Void, Never>?
    private var currentToken: Token?

    var isRunning: Bool { currentToken != nil }

    @discardableResult
    func start(
        _ operation: @escaping @MainActor (Token) async -> Void
    ) -> Token {
        cancel()
        let token = Token(id: UUID())
        currentToken = token
        task = Task { await operation(token) }
        return token
    }

    func accepts(_ token: Token) -> Bool {
        currentToken == token && !Task.isCancelled
    }

    @discardableResult
    func finish(_ token: Token) -> Bool {
        guard currentToken == token else { return false }
        currentToken = nil
        task = nil
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard task != nil || currentToken != nil else { return false }
        currentToken = nil
        task?.cancel()
        task = nil
        return true
    }
}
