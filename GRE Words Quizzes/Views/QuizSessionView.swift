//
//  QuizSessionView.swift
//  GRE Words Quizzes
//
//  The shared spoken-session visuals (masked word, hint dots, live mic
//  indicator, and the conversation transcript) driven by a QuizEngine. Used by
//  both the Practice tab and the Ebbinghaus review session so they look and
//  behave identically.
//

import SwiftUI

struct QuizSessionView: View {
    let engine: QuizEngine

    var body: some View {
        VStack(spacing: 0) {
            wordCard
            transcriptList
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

    // MARK: - Phase styling

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

struct TranscriptBubble: View {
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
