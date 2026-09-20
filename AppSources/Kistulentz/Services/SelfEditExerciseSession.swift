import Foundation

/// Tracks navigation and per-exercise progress for one `SelfEditExerciseView` session: which
/// exercise is current, each exercise's in-progress attempt text, and which exercises have had
/// Kistulentz's suggestion revealed. Pulled out of the view itself so this logic -- previously
/// reachable only through a UI test -- is directly unit-testable, and so it counts toward this
/// app's line-coverage baseline the same way `Views/` deliberately does not.
@MainActor
final class SelfEditExerciseSession: ObservableObject {
    let exercises: [SelfEditExercise]
    @Published private(set) var index = 0
    @Published private var attempts: [UUID: String] = [:]
    @Published private var revealed: Set<UUID> = []

    init(exercises: [SelfEditExercise]) {
        self.exercises = exercises
    }

    var current: SelfEditExercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }

    var isAtLastExercise: Bool {
        index >= exercises.count - 1
    }

    func attempt(for exercise: SelfEditExercise) -> String {
        attempts[exercise.id] ?? ""
    }

    func setAttempt(_ text: String, for exercise: SelfEditExercise) {
        attempts[exercise.id] = text
    }

    func isRevealed(_ exercise: SelfEditExercise) -> Bool {
        revealed.contains(exercise.id)
    }

    func reveal(_ exercise: SelfEditExercise) {
        revealed.insert(exercise.id)
    }

    func goToPrevious() {
        guard index > 0 else { return }
        index -= 1
    }

    func goToNext() {
        guard index < exercises.count - 1 else { return }
        index += 1
    }
}
