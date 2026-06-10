//
//  ProgressDashboardView.swift
//  GRE Words Quizzes
//
//  Lets the user plan a daily word goal (default 15) and tracks their study
//  history on a month calendar. Each day is colored by how much of that day's
//  goal was completed; days that met the goal are filled green.
//

import SwiftUI
import CoreData

struct ProgressDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DailyProgress.date, ascending: true)],
        animation: .default)
    private var days: FetchedResults<DailyProgress>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "highFrequency == YES"))
    private var highFreqWords: FetchedResults<GREWord>

    @AppStorage(ProgressStore.dailyGoalKey) private var dailyGoal: Int = ProgressStore.defaultDailyGoal
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())

    private var progressByDay: [Date: DailyProgress] {
        var map: [Date: DailyProgress] = [:]
        for row in days {
            if let date = row.date {
                map[Calendar.current.startOfDay(for: date)] = row
            }
        }
        return map
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    goalCard
                    todayCard
                    highFrequencyCard
                    statsRow
                    calendarCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
        }
        .onAppear {
            ProgressStore.seedSampleDataIfRequested(context: viewContext)
        }
    }

    // MARK: - Daily goal planner

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Daily goal", systemImage: "target")
                .font(.headline)
            Text("Plan how many words to study each day.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button { if dailyGoal > 1 { dailyGoal -= 1 } } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 0) {
                    Text("\(dailyGoal)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("words / day")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { if dailyGoal < 100 { dailyGoal += 1 } } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
            .tint(.accentColor)
            HStack(spacing: 8) {
                ForEach([10, 15, 20, 30], id: \.self) { preset in
                    Button("\(preset)") { dailyGoal = preset }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(dailyGoal == preset ? Color.accentColor : Color(.systemGray5),
                                    in: Capsule())
                        .foregroundStyle(dailyGoal == preset ? .white : .primary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Today

    private var todayCard: some View {
        let studied = ProgressStore.studiedToday(context: viewContext)
        let fraction = min(1.0, Double(studied) / Double(max(1, dailyGoal)))
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fraction >= 1 ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(studied)").font(.title2.bold().monospacedDigit())
                    Text("/ \(dailyGoal)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .animation(.easeInOut, value: fraction)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.headline)
                if studied >= dailyGoal {
                    Label("Goal reached — nicely done!", systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.green)
                } else {
                    Text("\(dailyGoal - studied) more to hit today's goal.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var highFrequencyCard: some View {
        let total = highFreqWords.count
        let mastered = highFreqWords.reduce(0) { $0 + (QuizEngine.isMastered($1) ? 1 : 0) }
        let fraction = total > 0 ? Double(mastered) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("High-frequency words", systemImage: "star.fill")
                    .font(.headline).foregroundStyle(.orange)
                Spacer()
                Text("\(mastered)/\(total)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("The most commonly tested GRE words. Practice prioritizes these first so you master them early.")
                .font(.caption).foregroundStyle(.secondary)
            ProgressView(value: fraction).tint(.orange)
            Text("\(Int(fraction * 100))% mastered")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(value: "\(ProgressStore.currentStreak(context: viewContext))",
                     label: "Day streak", icon: "flame.fill", color: .orange)
            statTile(value: "\(totalStudied)", label: "Words studied", icon: "books.vertical.fill", color: .blue)
            statTile(value: "\(daysMetGoal)", label: "Goal days", icon: "calendar.badge.checkmark", color: .green)
        }
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
            }
            .padding(.horizontal, 4)

            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(date: day, progress: progressByDay[Calendar.current.startOfDay(for: day)])
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }

            legend
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: .green, text: "Goal met")
            legendItem(color: .accentColor.opacity(0.45), text: "Partial")
            legendItem(color: Color(.systemGray5), text: "None")
            Spacer()
        }
        .font(.caption2)
        .padding(.top, 4)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: 12)
            Text(text).foregroundStyle(.secondary)
        }
    }

    // MARK: - Derived values

    private var totalStudied: Int { days.reduce(0) { $0 + Int($1.studiedCount) } }
    private var daysMetGoal: Int { days.filter { $0.metGoal }.count }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// Days of the displayed month padded with nils for leading blanks.
    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                cells.append(date)
            }
        }
        return cells
    }

    private func changeMonth(_ delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

private struct DayCell: View {
    let date: Date
    let progress: DailyProgress?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var dayNumber: String { "\(Calendar.current.component(.day, from: date))" }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(fillColor)
            if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            Text(dayNumber)
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(textColor)
        }
        .frame(height: 38)
    }

    private var fillColor: Color {
        guard let progress, progress.studiedCount > 0 else { return Color(.systemGray6) }
        if progress.metGoal { return .green }
        return Color.accentColor.opacity(0.25 + 0.5 * progress.fraction)
    }

    private var textColor: Color {
        guard let progress, progress.studiedCount > 0 else {
            return Calendar.current.isDate(date, inSameDayAs: Date()) || date <= Date() ? .primary : .secondary
        }
        return progress.metGoal ? .white : .primary
    }
}

#Preview {
    ProgressDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
