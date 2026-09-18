import SwiftUI

struct ReadabilitySidebar: View {
    let stats: WritingStats
    let issues: [WritingIssue]
    let targetGrade: Int
    let isUsingBenepar: Bool
    let isAnalyzingStructure: Bool
    let onSelect: (WritingIssue) -> Void

    private let categories: [IssueCategory] = [
        .adverb, .passiveVoice, .structuralComplexity, .complexPhrase, .aiTell, .avoidedWord,
        .hardSentence, .veryHardSentence
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READABILITY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text("Make every sentence earn its place.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if isAnalyzingStructure {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Checking sentence structure locally…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if isUsingBenepar {
                    Label("Benepar structural analysis active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                GradeComparisonCard(
                    gradeLevel: stats.gradeLevel,
                    targetGrade: targetGrade
                )

                HStack(spacing: 0) {
                    StatCell(value: "\(stats.words)", label: "WORDS")
                    StatCell(value: "\(stats.sentences)", label: "SENTENCES")
                    StatCell(value: "\(stats.readingMinutes)m", label: "READ")
                }
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("HIGHLIGHTS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    ForEach(categories) { category in
                        let matches = issues.filter { $0.category == category }
                        Button {
                            if let first = matches.first { onSelect(first) }
                        } label: {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(category.color)
                                    .frame(width: 11, height: 11)
                                Text(category.shortLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(matches.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(matches.isEmpty)
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.68))
    }
}

private struct GradeComparisonCard: View {
    let gradeLevel: Double
    let targetGrade: Int

    private let maximumGrade = 18.0

    private var targetStatus: ReadabilityTargetStatus {
        .classify(gradeLevel: gradeLevel, targetGrade: targetGrade)
    }

    private var statusColor: Color {
        targetStatus == .onTarget ? .green : .orange
    }

    private var statusTitle: String {
        switch targetStatus {
        case .onTarget: "On target"
        case .aboveTarget: "Revise for clarity"
        case .belowTarget: "Below target"
        }
    }

    private var differenceDescription: String {
        let difference = gradeLevel - Double(targetGrade)
        let magnitude = abs(difference)

        guard magnitude >= 0.05 else { return "Matches target grade" }

        let amount = magnitude.formatted(.number.precision(.fractionLength(1)))
        let unit = abs(magnitude - 1) < 0.05 ? "grade" : "grades"
        return "\(amount) \(unit) \(difference > 0 ? "above" : "below") target"
    }

    private var accessibilitySummary: String {
        let current = gradeLevel.formatted(.number.precision(.fractionLength(1)))
        return "Current grade \(current). Target grade \(targetGrade). \(statusTitle). \(differenceDescription)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(gradeLevel, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("CURRENT GRADE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Text(differenceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 10, 0)
                let currentX = 5 + plotWidth * gradeFraction(gradeLevel)
                let targetX = 5 + plotWidth * gradeFraction(Double(targetGrade))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 8)

                    Rectangle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 16)
                        .position(x: targetX, y: 8)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                        .position(x: currentX, y: 8)
                }
            }
            .frame(height: 16)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text("Current \(gradeLevel.formatted(.number.precision(.fractionLength(1))))")
                }
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 10)
                    Text("Target \(targetGrade)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("0")
                Spacer()
                Text("Grade level")
                Spacer()
                Text("18")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readability grade")
        .accessibilityValue(accessibilitySummary)
    }

    private func gradeFraction(_ grade: Double) -> CGFloat {
        CGFloat(max(0, min(maximumGrade, grade)) / maximumGrade)
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ReviewSidebar: View {
    let issues: [WritingIssue]
    let isRewriting: Bool
    let hasAPIKey: Bool
    let isPracticeModeEnabled: Bool
    let reference: EPUBReference?
    let alignment: ReferenceAlignment
    let isLoadingReference: Bool
    let onRunReview: () -> Void
    let onChooseReference: () -> Void
    let onRemoveReference: () -> Void
    let onSelect: (WritingIssue) -> Void
    let onApply: (WritingIssue) -> Void
    let onDecline: (WritingIssue) -> Void
    let onRewrite: (WritingIssue) -> Void
    let onApplyAll: () -> Void

    private var hasApplicableSuggestions: Bool {
        issues.contains {
            $0.replacement != nil && $0.replacement != $0.excerpt
                && !(isPracticeModeEnabled && $0.category.practicePrompt != nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.headline)
                    Text("\(issues.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasApplicableSuggestions {
                    Button("Apply All", action: onApplyAll)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Apply concrete, non-overlapping changes")
                }
                Button(action: onRunReview) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Run a safe local polish")
                .accessibilityLabel("Run a safe local polish")
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ReferenceCard(
                        reference: reference,
                        alignment: alignment,
                        isLoading: isLoadingReference,
                        onChoose: onChooseReference,
                        onRemove: onRemoveReference
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            isPracticeModeEnabled ? "Local Polish is off in Practice Mode" : "Local Polish is ready",
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption.weight(.semibold))
                        Text(isPracticeModeEnabled
                            ? "Fix flagged passages yourself while Practice Mode is on. Turn it off in the highlights menu to use Local Polish again."
                            : "Kistulentz can review and apply concrete built-in corrections without sending text anywhere. Advisory changes that require rewriting stay as highlights.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Polish Locally", action: onRunReview)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isPracticeModeEnabled)
                    }
                    .padding(12)
                    .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))

                    ForEach(issues) { issue in
                        IssueCard(
                            issue: issue,
                            canRewrite: hasAPIKey && !isRewriting,
                            isPracticeModeEnabled: isPracticeModeEnabled,
                            onSelect: onSelect,
                            onApply: onApply,
                            onDecline: onDecline,
                            onRewrite: onRewrite
                        )
                    }

                    if issues.isEmpty {
                        ContentUnavailableView(
                            "No local flags",
                            systemImage: "checkmark.circle",
                            description: Text(hasAPIKey
                                ? "Select a passage to try an AI rewrite for deeper grammar and phrasing suggestions."
                                : "Local analysis is clear. Set up Ollama or a cloud provider only when you want generative rewriting.")
                        )
                        .padding(.top, 12)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }
}

private struct ReferenceCard: View {
    let reference: EPUBReference?
    let alignment: ReferenceAlignment
    let isLoading: Bool
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyzing EPUB locally…")
                            .font(.callout.weight(.semibold))
                        Text("Finding voice, tone, characters, and tempo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let reference {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        if let author = reference.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(alignment.score)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("MATCH")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { profileBadges(reference.profile) }
                    VStack(alignment: .leading, spacing: 5) { profileBadges(reference.profile) }
                }

                ForEach(Array(alignment.notes.prefix(3))) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: note.isAligned ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(note.isAligned ? Color.green : Color.orange)
                        Text("\(note.title): \(note.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !reference.profile.characters.isEmpty {
                    Text("Characters: \(reference.profile.characters.prefix(8).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(reference.sourceCount == 1
                    ? "The reference stays local. Selected excerpts are sent only when you confirm an AI-backed Polish."
                    : "\(reference.sourceCount) books are combined locally. Selected excerpts are sent only when you confirm an AI-backed Polish.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Choose References", action: onChoose)
                        .controlSize(.small)
                    Button("Remove", role: .destructive, action: onRemove)
                        .controlSize(.small)
                }
            } else {
                Label("Writing references", systemImage: "books.vertical")
                    .font(.callout.weight(.semibold))
                Text("Compare this draft with a book’s voice, vocabulary, tone, characters, continuity, and tempo. The first analysis runs entirely on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Reference Library", action: onChoose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func profileBadges(_ profile: ReferenceProfile) -> some View {
        ReferenceBadge(text: profile.voice.capitalized)
        ReferenceBadge(text: profile.tempo.capitalized)
        ReferenceBadge(text: "Grade \(profile.gradeLevel.formatted(.number.precision(.fractionLength(1))))")
    }
}

private struct ReferenceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.background.opacity(0.75), in: Capsule())
    }
}

private struct IssueCard: View {
    let issue: WritingIssue
    let canRewrite: Bool
    let isPracticeModeEnabled: Bool
    let onSelect: (WritingIssue) -> Void
    let onApply: (WritingIssue) -> Void
    let onDecline: (WritingIssue) -> Void
    let onRewrite: (WritingIssue) -> Void

    /// Non-nil exactly when this specific card should withhold its fix: Practice Mode is on and
    /// this issue's category has a craft judgment worth practicing (`IssueCategory.practicePrompt`
    /// is nil for objective corrections like spelling/grammar, which stay fixable either way).
    private var practicePrompt: String? {
        isPracticeModeEnabled ? issue.category.practicePrompt : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onSelect(issue)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Circle()
                            .fill(issue.category.color)
                            .frame(width: 8, height: 8)
                        Text(issue.category.title)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if issue.source == .ai {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(issue.excerpt)
                        .font(.system(size: 13, design: .rounded))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let practicePrompt {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(practicePrompt)
                        .font(.system(size: 12.5, weight: .medium))
                        .italic()
                        .lineLimit(3)
                }
            } else if let replacement = issue.replacement {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(replacement)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(3)
                }
            }

            HStack(spacing: 7) {
                Spacer()
                Button("Decline") { onDecline(issue) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                if practicePrompt != nil {
                    // Withhold the fix -- the prompt above is the only response for this card.
                } else if issue.replacement != nil {
                    Button("Accept") { onApply(issue) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                } else {
                    Button("Rewrite…") { onRewrite(issue) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(!canRewrite)
                        .help(canRewrite
                            ? "Create three alternatives that address this card"
                            : "Connect or choose an AI provider to create alternatives")
                }
            }
        }
        .padding(11)
        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(issue.category.color)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
    }
}
