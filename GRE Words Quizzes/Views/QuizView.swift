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
                wordCard
                transcriptList
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
                sessionSize = max(1, remainingToday > 0 ? remainingToday : dailyGoal)
            }
        }
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

    // MARK: - Word card

    private var wordCard: some View {
        VStack(spacing: 14) {
            Text(phaseLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseColor)
                .textCase(.uppercase)

            Text(engine.revealedWord ?? (engine.maskedWord.isEmpty ? "GRE" : engine.maskedWord))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(engine.revealedWord == nil ? Color.primary : Color.green)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.opacity)

            hintDots

            ZStack {
                if engine.phase == .listening {
                    listeningIndicator
                } else if !engine.livePartial.isEmpty {
                    Text("“\(engine.livePartial)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(engine.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(phaseColor.opacity(0.4), lineWidth: engine.phase == .listening ? 2 : 0)
        )
        .padding()
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
    }

    private var hintDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < engine.hintsRevealedCount ? phaseColor : Color(.systemGray4))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
            Text(engine.livePartial.isEmpty ? "Listening…" : "“\(engine.livePartial)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Transcript

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if engine.transcript.isEmpty {
                        emptyState
                    }
                    ForEach(engine.transcript) { entry in
                        TranscriptBubble(entry: entry).id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onChange(of: engine.transcript.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Listen to the spoken clues, wait for the beeps, then say the word out loud.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
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

    private var phaseLabel: String {
        switch engine.phase {
        case .idle: return "Ready"
        case .speaking: return "Giving a clue"
        case .listening: return "Your turn"
        case .evaluating: return "Checking"
        case .revealing: return "Answer"
        case .finished: return "Finished"
        }
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .listening: return .red
        case .speaking: return .blue
        case .revealing, .finished: return .green
        default: return .accentColor
        }
    }
}

private struct TranscriptBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(roleTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(roleColor)
                Text(entry.text)
                    .font(.callout)
                    .foregroundStyle(entry.role == .system ? .secondary : .primary)
            }
            .padding(10)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 14))
            if entry.role != .user { Spacer(minLength: 40) }
        }
    }

    private var roleTitle: String {
        switch entry.role {
        case .app: return "App"
        case .user: return "You"
        case .system: return "Status"
        }
    }

    private var roleColor: Color {
        switch entry.role {
        case .app: return .blue
        case .user: return .green
        case .system: return .secondary
        }
    }

    private var bubbleColor: Color {
        switch entry.role {
        case .app: return Color.blue.opacity(0.12)
        case .user: return Color.green.opacity(0.15)
        case .system: return Color(.systemGray5).opacity(0.6)
        }
    }
}

#Preview {
    QuizView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
