//
//  ReviewScheduler.swift
//  GRE Words Quizzes
//
//  Spaced-repetition scheduling based on the Ebbinghaus forgetting curve.
//
//  Each studied word carries a `reviewStage` that indexes into a table of
//  increasing intervals (1, 2, 4, 7, 15, 30, 60, 120 days). Every time a word
//  is answered, the schedule advances (on a correct answer the interval grows;
//  on a miss it steps back so the word is seen again sooner). A word becomes a
//  "review candidate" once it has a `nextReviewDate`, and it is "due" when that
//  date has arrived. The daily review session randomly samples from the due
//  words so reviews stay varied while honoring the forgetting curve.
//

import Foundation
import CoreData

enum ReviewScheduler {
    /// Ebbinghaus-style spacing, in days, indexed by `reviewStage`.
    /// The gap between successive reviews grows as recall strengthens.
    static let intervals: [Int] = [1, 2, 4, 7, 15, 30, 60, 120]

    static var maxStage: Int16 { Int16(intervals.count - 1) }

    /// Updates a word's review schedule after it is answered (in practice or in
    /// a review session). Correct answers push the next review further out along
    /// the forgetting curve; misses pull it back so it returns sooner.
    static func schedule(word: GREWord, correct: Bool, now: Date = Date()) {
        if word.learnedAt == nil {
            word.learnedAt = now
        }

        if correct {
            word.reviewStage = min(word.reviewStage + 1, maxStage)
        } else {
            // A miss means the curve "reset" — relearn from the shortest interval.
            word.reviewStage = 0
        }

        let days = intervals[Int(max(0, min(word.reviewStage, maxStage)))]
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: now)
        word.nextReviewDate = calendar.date(byAdding: .day, value: days, to: base)
        word.lastReviewed = now
    }

    /// Words whose scheduled review date has arrived (due today or overdue),
    /// randomly sampled up to `limit`. Overdue words are favored slightly by
    /// including them all in the candidate pool before shuffling.
    static func dueWords(context: NSManagedObjectContext, limit: Int, now: Date = Date()) -> [GREWord] {
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let request = NSFetchRequest<GREWord>(entityName: "GREWord")
        request.predicate = NSPredicate(format: "nextReviewDate != nil AND nextReviewDate < %@", endOfToday as NSDate)
        let due = (try? context.fetch(request)) ?? []
        guard limit > 0 else { return [] }
        return Array(due.shuffled().prefix(limit))
    }

    /// Count of words due for review today (or overdue).
    static func dueCount(context: NSManagedObjectContext, now: Date = Date()) -> Int {
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let request = NSFetchRequest<NSNumber>(entityName: "GREWord")
        request.resultType = .countResultType
        request.predicate = NSPredicate(format: "nextReviewDate != nil AND nextReviewDate < %@", endOfToday as NSDate)
        return (try? context.count(for: request)) ?? 0
    }

    /// Initializes a schedule for words that were practiced before this feature
    /// existed (they have study history but no `nextReviewDate`). Estimates a
    /// stage from how many times they were answered correctly. Cheap no-op once
    /// the backfill has run.
    static func backfillIfNeeded(context: NSManagedObjectContext) {
        let request = NSFetchRequest<GREWord>(entityName: "GREWord")
        request.predicate = NSPredicate(format: "timesSeen > 0 AND nextReviewDate == nil")
        request.fetchLimit = 5_000
        guard let words = try? context.fetch(request), !words.isEmpty else { return }

        let calendar = Calendar.current
        for word in words {
            let learned = word.lastReviewed ?? word.addedAt ?? Date()
            word.learnedAt = learned
            let stage = Int16(max(0, min(Int(word.timesCorrect), Int(maxStage))))
            word.reviewStage = stage
            let days = intervals[Int(stage)]
            let base = calendar.startOfDay(for: learned)
            word.nextReviewDate = calendar.date(byAdding: .day, value: days, to: base)
        }
        try? context.save()
    }

    /// Screenshot-only helper: marks a spread of words as practiced across the
    /// past few days with review schedules (some due today) so the Review tab
    /// looks alive in marketing captures. Runs only when the `seedSampleReviews`
    /// launch flag is set and there's no real study history yet.
    static func seedSampleReviewsIfRequested(context: NSManagedObjectContext) {
        guard UserDefaults.standard.bool(forKey: "seedSampleReviews") else { return }

        let existing = NSFetchRequest<NSNumber>(entityName: "GREWord")
        existing.resultType = .countResultType
        existing.predicate = NSPredicate(format: "timesSeen > 0")
        if let n = try? context.count(for: existing), n > 0 { return }

        let fetch = NSFetchRequest<GREWord>(entityName: "GREWord")
        fetch.predicate = NSPredicate(format: "highFrequency == YES")
        fetch.sortDescriptors = [NSSortDescriptor(key: "word", ascending: true)]
        fetch.fetchLimit = 42
        guard let words = try? context.fetch(fetch), !words.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for (index, word) in words.enumerated() {
            let daysAgo = index % 6
            word.lastReviewed = calendar.date(byAdding: .day, value: -daysAgo, to: Date())
            word.learnedAt = calendar.date(byAdding: .day, value: -(daysAgo + 1), to: today)
            word.timesSeen = Int32(1 + index % 3)
            word.timesCorrect = Int32(index % 3)
            let stage = Int16(index % 4)
            word.reviewStage = stage
            // Roughly a third are due today; the rest are scheduled ahead.
            if index % 3 == 0 {
                word.nextReviewDate = today
            } else {
                word.nextReviewDate = calendar.date(byAdding: .day, value: 1 + index % 5, to: today)
            }
        }
        try? context.save()
    }

    /// A short, human-readable description of when a word is next due.
    static func nextReviewDescription(for word: GREWord, now: Date = Date()) -> String? {
        guard let next = word.nextReviewDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: next)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if days <= 0 { return "Due for review" }
        if days == 1 { return "Next review tomorrow" }
        return "Next review in \(days) days"
    }
}
