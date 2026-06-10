//
//  QuizView.swift
//  GRE Words Quizzes
//
//  The spoken practice screen: shows the masked word, the hint progress, a live
//  microphone indicator, and the full text transcript of the conversation.
//

import SwiftUI
import CoreData

struct QuizView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \GREWord.word, ascending: true)],
        animation: .default)
    private var words: FetchedResults<GREWord>

    @State private var engine = QuizEngine(context: PersistenceController.shared.container.viewContext)
    @State private var authorized: Bool? = nil
    @AppStorage(ProgressStore.dailyGoalKey) private var dailyGoal: Int = ProgressStore.defaultDailyGoal
    @AppStorage("focusHighFrequency") private var focusHighFrequency: Bool = true
    @State private var sessionSize: Int = ProgressStore.defaultDailyGoal

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                QuizSessionView(engine: engine)
                controlBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if authorized == nil && !UserDefaults.standard.bool(forKey: "uiTestMode") {
                authorized = await SpeechListener.requestAuthorization()
            }
        }
        .onAppear {
            if !engine.isSessionActive {
                sessionSize = suggestedSessionSize
            }
        }
        .onChange(of: engine.isSessionActive) { _, active in
            // When a session ends (Stop or finished), resize the next session to
            // the words still remaining for today so totals don't overshoot the
            // daily goal.
            if !active {
                sessionSize = suggestedSessionSize
            }
        }
    }

    /// Default size for the next session: whatever is left of today's goal, or a
    /// fresh full goal once today's target has already been met.
    private var suggestedSessionSize: Int {
        max(1, remainingToday > 0 ? remainingToday : dailyGoal)
    }

    private var studiedToday: Int {
        ProgressStore.studiedToday(context: viewContext)
    }

    private var remainingToday: Int {
        max(0, dailyGoal - studiedToday)
    }

    // MARK: - Header

    private var statusHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Label(HintGenerator.shared.modelStatus, systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if engine.isSessionActive {
                    Text("\(engine.sessionIndex)/\(engine.sessionCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            dailyGoalBar
            if authorized == false {
                Text("Microphone & Speech access are required. Enable them in Settings to use voice answers.")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var dailyGoalBar: some View {
        let studied = studiedToday
        let fraction = min(1.0, Double(studied) / Double(max(1, dailyGoal)))
        return VStack(spacing: 3) {
            HStack {
                Label("Today's goal", systemImage: "target")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(studied >= dailyGoal ? "\(studied)/\(dailyGoal) · done" : "\(studied)/\(dailyGoal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(studied >= dailyGoal ? .green : .secondary)
            }
            ProgressView(value: fraction)
                .tint(studied >= dailyGoal ? .green : .accentColor)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 10) {
            if !engine.isSessionActive {
                Toggle(isOn: $focusHighFrequency) {
                    Label("Focus on high-frequency words", systemImage: "star.fill")
                        .font(.subheadline)
                }
                .tint(.orange)
                Stepper("Words this session: \(sessionSize)",
                        value: $sessionSize, in: 1...100)
                    .font(.subheadline)
            }
            Button {
                if engine.isSessionActive {
                    engine.stop()
                } else {
                    startSession()
                }
            } label: {
                Label(engine.isSessionActive ? "Stop" : "Start Practice · \(sessionSize) words",
                      systemImage: engine.isSessionActive ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isSessionActive ? .red : .accentColor)
            .disabled(words.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    private func startSession() {
        let chosen = QuizEngine.selectWords(from: Array(words),
                                            count: sessionSize,
                                            focusHighFrequency: focusHighFrequency)
        engine.startSession(words: chosen)
    }
}

#Preview {
    QuizView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
