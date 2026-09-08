import SwiftUI

private enum PolishedDraftDecision {
    case accepted
    case declined
}

struct PolishedDraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: PolishedDraftPlan
    let onApplySelected: (Set<UUID>) -> Void
    let onReplaceAll: () -> Void

    @State private var decisions: [UUID: PolishedDraftDecision] = [:]
    @State private var showingReplaceAllConfirmation = false

    private var acceptedIDs: Set<UUID> {
        Set(decisions.compactMap { $0.value == .accepted ? $0.key : nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.origin == .local ? "Review Local Polish" : "Review Polished Draft")
                        .font(.title2.weight(.semibold))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !plan.isFullReplacementSafe {
                        let conflictCount = max(
                            plan.unsafeChanges.count,
                            plan.introducedDocumentRuleCategories.count
                        )
                        Label(
                            "Kistulentz blocked \(conflictCount) polished change\(conflictCount == 1 ? "" : "s") that would introduce new local flags.",
                            systemImage: "shield.lefthalf.filled.badge.checkmark"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(Array(plan.changes.enumerated()), id: \.element.id) { index, change in
                        PolishedDraftChangeCard(
                            number: index + 1,
                            change: change,
                            decision: decisions[change.id],
                            onAccept: { decisions[change.id] = .accepted },
                            onDecline: { decisions[change.id] = .declined }
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Text(acceptedIDs.isEmpty
                    ? "No passages selected"
                    : "\(acceptedIDs.count) passage\(acceptedIDs.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Replace All") {
                    showingReplaceAllConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(!plan.isFullReplacementSafe)
                .help(plan.isFullReplacementSafe
                    ? "Replace the document with the complete polished draft"
                    : "Replace All is unavailable because some passages conflict with local rules")
                Button("Apply Selected") {
                    onApplySelected(acceptedIDs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(acceptedIDs.isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 580, idealHeight: 720)
        .confirmationDialog(
            "Replace the entire document with the polished draft?",
            isPresented: $showingReplaceAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All", role: .destructive, action: onReplaceAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(plan.origin == .local
                ? "The complete local replacement will be one normal Undo action. No writing was sent anywhere."
                : "The complete replacement will be one normal Undo action. Your AI review will remain available.")
        }
    }

    private var summary: String {
        let count = plan.changes.count
        let source = plan.origin == .local
            ? "Built-in rules created these changes entirely on this Mac."
            : "The selected AI provider created these changes."
        return "\(source) Compare \(count) changed passage\(count == 1 ? "" : "s"). Accept individual changes, or replace the whole document after confirmation."
    }
}

private struct PolishedDraftChangeCard: View {
    let number: Int
    let change: PolishedDraftChange
    let decision: PolishedDraftDecision?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Passage \(number)")
                    .font(.caption.weight(.semibold))
                if !change.isSafe {
                    Label("Blocked", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if decision == .accepted {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if decision == .declined {
                    Label("Declined", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                passageColumn(title: "CURRENT", text: change.originalText, color: .red)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 25)
                passageColumn(title: "POLISHED", text: change.replacementText, color: .green)
            }

            if let message = change.safetyMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Spacer()
                decisionButton(
                    title: "Decline",
                    systemImage: "xmark",
                    isSelected: decision == .declined,
                    color: .secondary,
                    action: onDecline
                )
                decisionButton(
                    title: "Accept",
                    systemImage: "checkmark",
                    isSelected: decision == .accepted,
                    color: .accentColor,
                    action: onAccept
                )
                .disabled(!change.isSafe)
            }
        }
        .padding(14)
        .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(change.isSafe ? Color.secondary.opacity(0.15) : Color.orange.opacity(0.45))
        }
    }

    private func passageColumn(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func decisionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : color)
                .background(isSelected ? color : Color.clear, in: Capsule())
                .overlay {
                    Capsule().stroke(color.opacity(isSelected ? 0 : 0.45))
                }
        }
        .buttonStyle(.plain)
    }
}
