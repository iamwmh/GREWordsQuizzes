//
//  ProgressStore.swift
//  GRE Words Quizzes
//
//  Records and queries the user's daily study progress so the calendar and the
//  daily-goal indicators stay in sync. One `DailyProgress` row is kept per
//  calendar day (keyed by the start of that day).
//

import Foundation
import CoreData

enum ProgressStore {
    /// Shared key for the adjustable daily word goal (default 15).
    static let dailyGoalKey = "dailyWordGoal"
    static let defaultDailyGoal = 15

    static var dailyGoal: Int {
        let stored = UserDefaults.standard.integer(forKey: dailyGoalKey)
        return stored > 0 ? stored : defaultDailyGoal
    }

    /// Records that one word was studied today, updating the running counts.
    @discardableResult
    static func recordStudied(correct: Bool, context: NSManagedObjectContext) -> DailyProgress {
        let day = startOfDay()
        let progress = fetchOrCreate(day: day, context: context)
        progress.studiedCount += 1
        if correct { progress.correctCount += 1 }
        progress.goal = Int32(dailyGoal)
        try? context.save()
        return progress
    }

    /// Returns today's progress row if it exists.
    static func today(context: NSManagedObjectContext) -> DailyProgress? {
        progress(for: Date(), context: context)
    }

    static func progress(for date: Date, context: NSManagedObjectContext) -> DailyProgress? {
        let request = NSFetchRequest<DailyProgress>(entityName: "DailyProgress")
        request.predicate = NSPredicate(format: "date == %@", startOfDay(date) as NSDate)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Number of words studied today.
    static func studiedToday(context: NSManagedObjectContext) -> Int {
        Int(today(context: context)?.studiedCount ?? 0)
    }

    /// Current streak of consecutive days (ending today or yesterday) in which
    /// the daily goal was met.
    static func currentStreak(context: NSManagedObjectContext) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = startOfDay()

        // Allow the streak to remain "alive" if today is not yet finished.
        if let todayRow = progress(for: cursor, context: context),
           todayRow.studiedCount < todayRow.effectiveGoal {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        } else if progress(for: cursor, context: context) == nil {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        while let row = progress(for: cursor, context: context), row.metGoal {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Helpers

    private static func fetchOrCreate(day: Date, context: NSManagedObjectContext) -> DailyProgress {
        if let existing = progress(for: day, context: context) {
            return existing
        }
        let row = DailyProgress(context: context)
        row.date = day
        row.studiedCount = 0
        row.correctCount = 0
        row.goal = Int32(dailyGoal)
        return row
    }

    private static func startOfDay(_ date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Screenshot-only helper: fills recent days with sample activity so the
    /// calendar looks alive in marketing captures. Only runs when the
    /// `seedSampleProgress` launch flag is set and no data exists yet.
    static func seedSampleDataIfRequested(context: NSManagedObjectContext) {
        guard UserDefaults.standard.bool(forKey: "seedSampleProgress") else { return }
        let calendar = Calendar.current
        let goal = dailyGoal
        let pattern = [15, 18, 12, 20, 15, 0, 16, 22, 15, 15, 8, 17, 19, 0, 15, 21, 15, 14, 16, 11]
        for (offset, studied) in pattern.enumerated() where studied > 0 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfDay()) else { continue }
            if progress(for: day, context: context) != nil { continue }
            let row = DailyProgress(context: context)
            row.date = day
            row.studiedCount = Int32(studied)
            row.correctCount = Int32(Double(studied) * 0.8)
            row.goal = Int32(goal)
        }
        try? context.save()
    }
}

extension DailyProgress {
    /// The goal that applied that day, falling back to the current goal.
    var effectiveGoal: Int32 {
        goal > 0 ? goal : Int32(ProgressStore.dailyGoal)
    }

    var metGoal: Bool {
        studiedCount >= effectiveGoal
    }

    /// 0...1 completion fraction toward the goal.
    var fraction: Double {
        let target = max(1, Int(effectiveGoal))
        return min(1.0, Double(studiedCount) / Double(target))
    }
}
