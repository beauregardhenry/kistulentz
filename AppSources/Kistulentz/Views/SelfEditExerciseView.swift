import SwiftUI

/// A structured, session-scoped practice set: attempt a fix on the writer's own flagged sentences
/// before Kistulentz reveals its own suggestion for comparison. Never overwrites the writer's
/// attempt and never touches the underlying `WritingIssue` -- skipping or finishing an exercise has
/// no effect on how that flag continues to appear in the regular editor view.
struct SelfEditExerciseView: View {
    let exercises: [SelfEditExercise]
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var attempts: [UUID: String] = [:]
    @State private var revealed: Set<UUID> = []

    private var current: SelfEditExercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }

    private func attemptBinding(for exercise: SelfEditExercise) -> Binding<String> {
        Binding(
            get: { attempts[exercise.id] ?? "" },
            set: { attempts[exercise.id] = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let current {
                ScrollView {
                    SelfEditExerciseCard(
                        exercise: current,
                        attempt: attemptBinding(for: current),
                        isRevealed: revealed.contains(current.id),
                        onReveal: { revealed.insert(current.id) }
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
                if !exercises.isEmpty {
                    Text("Exercise \(index + 1) of \(exercises.count)")
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
            Button("Previous") { index -= 1 }
                .disabled(index == 0)
            Spacer()
            Button(index == exercises.count - 1 ? "Finish" : "Next") {
                if index == exercises.count - 1 {
                    dismiss()
                } else {
                    index += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(exercises.isEmpty)
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
        .accessibilityIdentifier("SelfEditExerciseCard")
    }

    private func labeledBlock(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
    }
}
