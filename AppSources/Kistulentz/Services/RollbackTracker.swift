import Foundation

/// Runs a sequence of rollback steps after an operation has already failed partway through, and
/// escalates to a more specific error if any step *also* fails -- rather than the original error,
/// which would misleadingly imply the rollback fully undid the partial change. Used by every place
/// in this codebase that walks back a multi-step disk mutation: project-format migration, file
/// reorganization, systemic revision, heading splits, and project import.
///
/// When every step succeeds, rethrows `originalError` unchanged -- that's the existing,
/// well-tested "the rollback succeeded cleanly" behavior. Only escalates when at least one step's
/// own attempt throws, in which case `escalate` builds the specific error each call site wants
/// (naming both the original failure and what its rollback couldn't undo).
enum RollbackTracker {
    static func run(
        after originalError: Error,
        steps: [(label: String, attempt: () throws -> Void)],
        escalate: (_ originalReason: String, _ rollbackReason: String) -> Error
    ) throws -> Never {
        var failures: [String] = []
        for step in steps {
            do {
                try step.attempt()
            } catch {
                failures.append("\(step.label): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw escalate(originalError.localizedDescription, failures.joined(separator: "; "))
        }
        throw originalError
    }
}
