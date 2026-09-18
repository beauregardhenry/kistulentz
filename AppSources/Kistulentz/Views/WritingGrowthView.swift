import SwiftUI

/// Cross-project growth history: how accept/decline decisions for each issue category have
/// trended over the last several months, independent of any single project. See
/// `WritingGrowthStore` for why this is a separate signal from the per-project style-learning log.
struct WritingGrowthView: View {
    @ObservedObject var store: WritingGrowthStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    /// Most recent six recorded months, newest first -- older history stays on disk but isn't
    /// worth showing here; the point is a recent trend, not a permanent ledger.
    private var recentMonths: [WritingGrowthMonth] {
        Array(store.months.reversed().prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Writing Growth").font(.headline)
                    Text("How your accepted and declined flags have trended over time, across every project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !store.months.isEmpty {
                    Button("Clear Growth History", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()

            if recentMonths.isEmpty {
                ContentUnavailableView(
                    "No Growth History Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Accept or decline a few flagged passages, and Kistulentz will start tracking how your writing changes over time -- entirely on this Mac.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(recentMonths) { month in
                            WritingGrowthMonthSection(month: month)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .confirmationDialog(
            "Clear all writing growth history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Growth History", role: .destructive) {
                store.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the accepted/declined counts tracked across every project. It does not change any project's own files or learned style preferences.")
        }
    }
}

private struct WritingGrowthMonthSection: View {
    let month: WritingGrowthMonth

    private var displayName: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: month.key) else { return month.key }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }

    private var activeCategories: [(category: IssueCategory, tally: WritingGrowthTally)] {
        month.tallies
            .filter { $0.value.accepted > 0 || $0.value.declined > 0 }
            .map { (category: $0.key, tally: $0.value) }
            .sorted { $0.category.title < $1.category.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
            ForEach(activeCategories, id: \.category) { entry in
                WritingGrowthCategoryRow(category: entry.category, tally: entry.tally)
            }
        }
    }
}

private struct WritingGrowthCategoryRow: View {
    let category: IssueCategory
    let tally: WritingGrowthTally

    private var total: Int { tally.accepted + tally.declined }
    private var acceptedFraction: Double {
        total == 0 ? 0 : Double(tally.accepted) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.color)
                .frame(width: 7, height: 7)
            Text(category.title)
                .font(.caption)
                .frame(width: 130, alignment: .leading)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(category.color)
                        .frame(width: geometry.size.width * acceptedFraction)
                    Rectangle()
                        .fill(category.color.opacity(0.2))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            Text("\(tally.accepted) accepted, \(tally.declined) declined")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
    }
}
