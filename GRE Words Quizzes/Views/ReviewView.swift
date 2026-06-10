//
//  ReviewView.swift
//  GRE Words Quizzes
//
//  The Review tab. Two things live here:
//    1. "Today's review" — a spaced-repetition session that randomly samples
//       the words whose Ebbinghaus review date has arrived, then runs them
//       through the same spoken quiz as Practice.
//    2. "Practiced words" — a day-by-day list of every word you've studied,
//       so you can browse and revisit past words at any time.
//

import SwiftUI
import CoreData

struct ReviewView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \GREWord.lastReviewed, ascending: false)],
        predicate: NSPredicate(format: "timesSeen > 0"),
        animation: .default)
    private var practiced: FetchedResults<GREWord>

    @State private var engine = QuizEngine(context: PersistenceController.shared.container.viewContext)
    @State private var showingSession = false
    @State private var reviewSize = 20
    @State private var dueNow = 0
    @State private var authorized: Bool? = nil

    var body: some View {
        NavigationStack {
            List {
                Section { reviewCard }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                if practiced.isEmpty {
                    Section {
                        Text("Words you practice will appear here, grouped by day, so you can review them anytime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(grouped, id: \.day) { group in
                        Section {
                            ForEach(group.words) { word in
                                NavigationLink {
                                    WordDetailView(word: word)
                                } label: {
                                    WordRow(word: word)
                                }
                            }
                        } header: {
                            HStack {
                                Text(dayLabel(group.day))
                                Spacer()
                                Text("\(group.words.count) words")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review")
        }
        .task {
            if authorized == nil && !UserDefaults.standard.bool(forKey: "uiTestMode") {
                authorized = await SpeechListener.requestAuthorization()
            }
        }
        .onAppear {
            ReviewScheduler.seedSampleReviewsIfRequested(context: viewContext)
            ReviewScheduler.backfillIfNeeded(context: viewContext)
            refreshDue()
        }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            engine.stop()
            refreshDue()
        }) {
            reviewSession
        }
    }

    // MARK: - Today's review card

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's review", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(dueNow) due")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(dueNow > 0 ? .purple : .secondary)
            }

            Text("Spaced repetition based on the Ebbinghaus forgetting curve. Words come back for review right before you're likely to forget them — sooner if you miss, later as recall strengthens.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dueNow > 0 {
                Stepper("Review \(min(reviewSize, dueNow)) words now",
                        value: $reviewSize, in: 1...dueNow)
                    .font(.subheadline)
                Button {
                    startReview()
                } label: {
                    Label("Start review · \(min(reviewSize, dueNow)) words", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else {
                Text(practiced.isEmpty
                     ? "Practice some words first — they'll be scheduled for review automatically."
                     : "You're all caught up. New reviews will be ready soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Review session (presented full-screen)

    private var reviewSession: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QuizSessionView(engine: engine)
                Button {
                    if engine.isSessionActive {
                        engine.stop()
                    } else {
                        showingSession = false
                    }
                } label: {
                    Label(engine.isSessionActive ? "Stop review" : "Done",
                          systemImage: engine.isSessionActive ? "stop.fill" : "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isSessionActive ? .red : .green)
                .padding()
                .background(.bar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        engine.stop()
                        showingSession = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var grouped: [(day: Date, words: [GREWord])] {
        let calendar = Calendar.current
        let dict = Dictionary(grouping: practiced.compactMap { word -> (Date, GREWord)? in
            guard let reviewed = word.lastReviewed else { return nil }
            return (calendar.startOfDay(for: reviewed), word)
        }, by: { $0.0 })
        return dict
            .map { (day: $0.key, words: $0.value.map(\.1).sorted { ($0.word ?? "") < ($1.word ?? "") }) }
            .sorted { $0.day > $1.day }
    }

    private func refreshDue() {
        dueNow = ReviewScheduler.dueCount(context: viewContext)
        if reviewSize > dueNow { reviewSize = max(1, min(20, dueNow)) }
        if dueNow > 0 && reviewSize < 1 { reviewSize = min(20, dueNow) }
    }

    private func startReview() {
        let count = min(reviewSize, dueNow)
        let due = ReviewScheduler.dueWords(context: viewContext, limit: count)
        guard !due.isEmpty else { return }
        engine.startSession(words: due)
        showingSession = true
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    ReviewView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
