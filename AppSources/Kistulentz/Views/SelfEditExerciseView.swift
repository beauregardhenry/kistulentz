import SwiftUI

/// A structured, session-scoped practice set: attempt a fix on the writer's own flagged sentences
/// before Kistulentz reveals its own suggestion for comparison. Never overwrites the writer's
/// attempt and never touches the underlying `WritingIssue` -- skipping or finishing an exercise has
/// no effect on how that flag continues to appear in the regular editor view.
struct SelfEditExerciseView: View {
    @StateObject private var session: SelfEditExerciseSession
    @Environment(\.dismiss) private var dismiss

    init(exercises: [SelfEditExercise]) {
        _session = StateObject(wrappedValue: SelfEditExerciseSession(exercises: exercises))
    }

    private func attemptBinding(for exercise: SelfEditExercise) -> Binding<String> {
        Binding(
            get: { session.attempt(for: exercise) },
            set: { session.setAttempt($0, for: exercise) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let current = session.current {
                ScrollView {
                    SelfEditExerciseCard(
                        exercise: current,
                        attempt: attemptBinding(for: current),
                        isRevealed: session.isRevealed(current),
                        onReveal: { session.reveal(current) }
                    )
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "No Exercises Yet",
                    systemImage: "pencil.and.outline",
                    description: Text("Kistulentz builds these from your own flagged sentences. Keep writing, and there will be some to practice on.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 460, idealHeight: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Self-Edit Exercises").font(.headline)
                if !session.exercises.isEmpty {
                    Text("Exercise \(session.index + 1) of \(session.exercises.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Button("Previous") { session.goToPrevious() }
                .disabled(session.index == 0)
            Spacer()
            Button(session.isAtLastExercise ? "Finish" : "Next") {
                if session.isAtLastExercise {
                    dismiss()
                } else {
                    session.goToNext()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.exercises.isEmpty)
        }
        .padding(14)
    }
}

private struct SelfEditExerciseCard: View {
    let exercise: SelfEditExercise
    @Binding var attempt: String
    let isRevealed: Bool
    let onReveal: () -> Void

    private var issue: WritingIssue { exercise.issue }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(issue.category.color).frame(width: 7, height: 7)
                Text(issue.category.title).font(.caption.weight(.semibold))
            }

            labeledBlock(title: "FLAGGED PASSAGE") {
                Text(issue.excerpt)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(issue.category.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Text(issue.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let prompt = issue.category.practicePrompt {
                Text(prompt).font(.callout.weight(.medium))
            }

            labeledBlock(title: "YOUR ATTEMPT") {
                TextEditor(text: $attempt)
                    .font(.system(size: 14))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25))
                    }
            }

            if isRevealed {
                labeledBlock(title: "KISTULENTZ'S SUGGESTION") {
                    if let replacement = issue.replacement {
                        Text(replacement)
                            .font(.system(size: 14, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("There's no single mechanical fix Kistulentz would apply here -- this is exactly the kind of judgment call worth practicing.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Reveal Kistulentz's Suggestion", action: onReveal)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func labeledBlock(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
    }
}
