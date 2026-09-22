import SwiftUI

/// Cross-project growth history: how accept/decline decisions for each issue category have
/// trended over the last several months, independent of any single project. See
/// `WritingGrowthStore` for why this is a separate signal from the per-project style-learning log.
struct WritingGrowthView: View {
    @ObservedObject var store: WritingGrowthStore
    @EnvironmentObject private var writingActivity: WritingActivityStore
    @EnvironmentObject private var settings: AppSettings
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

            WritingActivitySection(activityStore: writingActivity, dailyWordGoal: settings.dailyWordGoal)
                .padding(16)
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
        .frame(minWidth: 560, minHeight: 620)
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

/// A GitHub-style calendar heatmap of writing activity, colored by craft quality rather than raw
/// volume -- see `WritingActivityStore` for why those are kept as two separate signals. A day's
/// *presence* here (any fill at all) is a pure "did I show up" streak signal; the *color* on top of
/// that is the only place quality shows up, ranked against the writer's own history so a messy
/// early-draft day in one genre isn't penalized the same as a different writer's polished pass.
private struct WritingActivitySection: View {
    @ObservedObject var activityStore: WritingActivityStore
    let dailyWordGoal: Int

    private let weeksShown = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                Label {
                    Text("\(activityStore.currentStreak)-day streak")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(activityStore.currentStreak > 0 ? .orange : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today: \(activityStore.today.wordsWritten) of \(dailyWordGoal) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(activityStore.today.wordsWritten), total: Double(max(dailyWordGoal, 1)))
                        .frame(width: 180)
                }

                Spacer()
            }

            heatmapGrid

            HStack(spacing: 4) {
                Text("Noisier").font(.caption2).foregroundStyle(.secondary)
                ForEach(WritingHeatLevel.allCases, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("Cleaner").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var heatmapGrid: some View {
        let weeks = Self.recentWeeks(weeksShown: weeksShown, today: Date(), calendar: .current)
        return HStack(alignment: .top, spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(week, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor(for: day))
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }

    private func fillColor(for day: Date) -> Color {
        guard day <= Date() else { return .clear }
        guard activityStore.days[WritingActivityStore.dayKey(for: day)] != nil else {
            return Color.secondary.opacity(0.12)
        }
        return Self.color(for: activityStore.heatLevel(for: day))
    }

    private static func color(for level: WritingHeatLevel) -> Color {
        switch level {
        case .none: Color.blue.opacity(0.35)
        case .q1: Color.red.opacity(0.55)
        case .q2: Color.orange.opacity(0.6)
        case .q3: Color.green.opacity(0.55)
        case .q4: Color.green.opacity(0.9)
        }
    }

    /// `weeksShown` columns of 7 dates each (Sunday first), the last column ending on the Saturday
    /// of the current week -- so today's cell lands wherever it falls in that final column, and any
    /// remaining days later in the current week are simply future dates the caller renders blank.
    private static func recentWeeks(weeksShown: Int, today: Date, calendar: Calendar) -> [[Date]] {
        let startOfToday = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: startOfToday)
        guard let endOfThisWeek = calendar.date(byAdding: .day, value: 7 - weekday, to: startOfToday) else {
            return []
        }
        return (0..<weeksShown).reversed().compactMap { weekOffset -> [Date]? in
            guard let weekEnd = calendar.date(byAdding: .day, value: -7 * weekOffset, to: endOfThisWeek) else {
                return nil
            }
            return (0..<7).reversed().compactMap { dayOffset in
                calendar.date(byAdding: .day, value: -dayOffset, to: weekEnd)
            }
        }
    }
}
