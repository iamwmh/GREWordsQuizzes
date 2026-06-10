//
//  QuizEngine.swift
//  GRE Words Quizzes
//
//  The heart of the app: an async state machine that runs the spoken
//  question-and-answer loop for a session of GRE words.
//
//  Per word the flow is:
//    1. Speak hint 1 (definition).  → beep-beep-beep → listen ~3s.
//    2. If silent, speak hint 2 (spelling). → beep → listen ~3s.
//    3. If still silent, speak hint 3 (characteristics). → beep → listen.
//    4. If all hints are exhausted with no / wrong answer, reveal the word.
//
//  If the user answers (incorrectly) before the third hint, the app asks
//  "Another chance or finish?" — "another chance" continues to the next hint,
//  "finish" reveals the answer immediately.
//

import Foundation
import CoreData
import Observation

/// A single line in the on-screen conversation transcript.
struct TranscriptEntry: Identifiable, Equatable {
    enum Role { case app, user, system }
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()
}

@MainActor
@Observable
final class QuizEngine {
    enum Phase: String {
        case idle, speaking, listening, evaluating, revealing, finished
    }

    // MARK: - Observable state (drives the UI)
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var phase: Phase = .idle
    private(set) var statusText = "Tap Start to begin"
    private(set) var livePartial = ""
    private(set) var maskedWord = ""
    private(set) var revealedWord: String?
    private(set) var currentDefinition = ""
    private(set) var hintsRevealedCount = 0
    private(set) var sessionTotal = 0
    private(set) var sessionCorrect = 0
    private(set) var sessionIndex = 0
    private(set) var sessionCount = 0
    private(set) var isSessionActive = false

    // MARK: - Dependencies
    private let context: NSManagedObjectContext
    private let narrator = Narrator()
    private let tones = TonePlayer()
    private let listener = SpeechListener()
    private let hintGenerator = HintGenerator.shared

    private var runTask: Task<Void, Never>?
    private var words: [GREWord] = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Session control

    func startSession(words: [GREWord]) {
        guard !words.isEmpty else { return }
        stop()
        self.words = words
        transcript = []
        sessionTotal = 0
        sessionCorrect = 0
        sessionIndex = 0
        sessionCount = words.count
        isSessionActive = true
        runTask = Task { [weak self] in
            await self?.runSession()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        listener.cancel()
        narrator.stop()
        tones.stop()
        if isSessionActive {
            phase = .idle
            statusText = "Stopped"
            isSessionActive = false
            AudioSessionManager.deactivate()
        }
    }

    // MARK: - Main loop

    private func runSession() async {
        AudioSessionManager.activate()
        await narrator.speak("Let's begin. Listen to each clue, then say the word.")

        for (index, word) in words.enumerated() {
            if Task.isCancelled { break }
            sessionIndex = index + 1
            await runRound(for: word)
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        if !Task.isCancelled {
            phase = .finished
            statusText = "Session complete"
            addEntry(.system, "Session complete — \(sessionCorrect) of \(sessionTotal) correct.")
            await narrator.speak("Session complete. You answered \(sessionCorrect) out of \(sessionTotal) correctly. Great work.")
        }
        isSessionActive = false
        AudioSessionManager.deactivate()
    }

    private func runRound(for word: GREWord) async {
        let answer = (word.word ?? "").lowercased()
        guard !answer.isEmpty else { return }

        sessionTotal += 1
        word.timesSeen += 1
        revealedWord = nil
        hintsRevealedCount = 0
        maskedWord = Self.mask(answer)
        currentDefinition = word.definition ?? ""
        addEntry(.system, "New word. Listen to the clues, then say the word.")

        statusText = "Thinking of clues…"
        let generated = await hintGenerator.hints(for: word, context: context)
        let hints = Self.roundHints(from: generated)

        var solved = false
        var hintIndex = 0

        while hintIndex < hints.count {
            if Task.isCancelled { return }

            let label = "Hint \(hintIndex + 1) · \(hints[hintIndex].kind.rawValue)"
            phase = .speaking
            statusText = label
            hintsRevealedCount = hintIndex + 1
            addEntry(.app, "\(label): \(hints[hintIndex].text)")
            await narrator.speak(hints[hintIndex].text)
            if Task.isCancelled { return }

            let result = await promptAndListen()
            if Task.isCancelled { return }

            guard result.didDetectSpeech, let said = result.transcript else {
                addEntry(.system, "No answer heard.")
                hintIndex += 1
                continue
            }

            addEntry(.user, said)

            if Self.isCorrect(said, answer: answer) {
                solved = true
                break
            }

            // Wrong answer.
            if hintIndex < hints.count - 1 {
                let choice = await askAnotherChanceOrFinish()
                if choice == .finish { break }
                hintIndex += 1
                continue
            } else {
                // Wrong even after the final hint.
                break
            }
        }

        await concludeRound(word: word, answer: answer, solved: solved)
    }

    private func concludeRound(word: GREWord, answer: String, solved: Bool) async {
        phase = .revealing
        revealedWord = answer
        maskedWord = answer

        if solved {
            sessionCorrect += 1
            word.timesCorrect += 1
            statusText = "Correct!"
            addEntry(.system, "Correct! The word is \"\(answer)\".")
            await narrator.speak("Correct! The word is \(answer).")
        } else {
            statusText = "Answer revealed"
            let def = word.definition ?? ""
            addEntry(.system, "The correct word is \"\(answer)\" — \(def)")
            await narrator.speak("The correct answer is \(answer). \(Self.spellOut(answer)). It means: \(def)")
        }

        // Update the Ebbinghaus review schedule for this word.
        ReviewScheduler.schedule(word: word, correct: solved)
        try? context.save()

        // Track the word against today's study goal/calendar.
        ProgressStore.recordStudied(correct: solved, context: context)
    }

    // MARK: - Listening helpers

    private func promptAndListen(initialTimeout: TimeInterval = 3.0) async -> ListenResult {
        phase = .listening
        statusText = "Listening…"
        livePartial = ""
        await tones.playReadyTones()
        if Task.isCancelled { return ListenResult(transcript: nil, didDetectSpeech: false) }
        listener.onPartial = { [weak self] text in self?.livePartial = text }
        let result = await listener.listen(initialTimeout: initialTimeout)
        livePartial = ""
        phase = .evaluating
        return result
    }

    private enum ChanceChoice { case another, finish }

    private func askAnotherChanceOrFinish() async -> ChanceChoice {
        let question = "Another chance, or finish?"
        phase = .speaking
        addEntry(.app, question)
        await narrator.speak(question)

        for attempt in 0..<2 {
            if Task.isCancelled { return .finish }
            let result = await promptAndListen(initialTimeout: 4.0)
            if result.didDetectSpeech, let said = result.transcript {
                addEntry(.user, said)
                let lower = said.lowercased()
                if lower.contains("finish") || lower.contains("done") ||
                    lower.contains("stop") || lower.contains("reveal") ||
                    lower.contains("answer") || lower.contains("give up") {
                    return .finish
                }
                if lower.contains("another") || lower.contains("chance") ||
                    lower.contains("continue") || lower.contains("again") ||
                    lower.contains("next") || lower.contains("hint") ||
                    lower.contains("more") || lower.contains("keep") {
                    return .another
                }
            }
            if attempt == 0 {
                addEntry(.system, "Please say \"another chance\" or \"finish\".")
                await narrator.speak("Please say, another chance, or finish.")
            }
        }
        // Default to giving the learner another chance.
        return .another
    }

    // MARK: - Transcript

    private func addEntry(_ role: TranscriptEntry.Role, _ text: String) {
        transcript.append(TranscriptEntry(role: role, text: text))
    }

    // MARK: - Matching utilities

    static func isCorrect(_ said: String, answer: String) -> Bool {
        let target = answer.lowercased()
        let tokens = said.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        if tokens.contains(target) { return true }
        let threshold = target.count <= 5 ? 1 : 2
        for token in tokens where levenshtein(token, target) <= threshold {
            return true
        }
        let joined = tokens.joined()
        if !joined.isEmpty, levenshtein(joined, target) <= threshold { return true }
        return false
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var curr = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            curr[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[y.count]
    }

    /// Whether a word counts as "mastered" for prioritization/stats.
    static func isMastered(_ word: GREWord) -> Bool {
        word.timesSeen > 0 && word.timesCorrect >= 2
    }

    /// Selects words for a session. When `focusHighFrequency` is on, commonly
    /// tested / high-frequency words (and weaker, less-practiced words) are
    /// prioritized; a small random window keeps sessions varied.
    static func selectWords(from words: [GREWord], count: Int, focusHighFrequency: Bool) -> [GREWord] {
        guard count > 0, !words.isEmpty else { return [] }
        guard focusHighFrequency else {
            return Array(words.shuffled().prefix(count))
        }

        func accuracy(_ w: GREWord) -> Double {
            w.timesSeen > 0 ? Double(w.timesCorrect) / Double(w.timesSeen) : 0
        }

        let sorted = words.sorted { a, b in
            let ma = isMastered(a), mb = isMastered(b)
            if ma != mb { return !ma }                 // unmastered first
            if a.priority != b.priority { return a.priority < b.priority } // higher tier first
            let aa = accuracy(a), ab = accuracy(b)
            if aa != ab { return aa < ab }             // weaker first
            return a.frequencyRank < b.frequencyRank   // more common first
        }

        let window = Array(sorted.prefix(max(count * 5, 150)))
        return Array(window.shuffled().prefix(count))
    }

    /// Builds the three clues for a round. The meaning-based clues (definition,
    /// characteristic, and — when available — a synonym or antonym) are shuffled
    /// so the synonym/antonym type appears in some rounds and not others, in a
    /// random position. The spelling clue is always given last as a final nudge.
    static func roundHints(from generated: GeneratedHints) -> [Hint] {
        var meaning: [Hint] = [Hint(kind: .definition, text: generated.definitionHint)]

        // Only add a characteristic clue if it's genuinely distinct.
        if let c = generated.characteristicHint, !c.isEmpty {
            meaning.append(Hint(kind: .characteristic, text: c))
        }

        // Mix in at most one relation clue per round (synonym OR antonym).
        var relations: [Hint] = []
        if let s = generated.synonymHint { relations.append(Hint(kind: .synonym, text: s)) }
        if let a = generated.antonymHint { relations.append(Hint(kind: .antonym, text: a)) }
        if let chosen = relations.randomElement() {
            meaning.append(chosen)
        }

        meaning.shuffle()

        // Pick up to two meaning clues, skipping any that duplicate the content
        // of one already chosen, so two hints never repeat each other.
        var picked: [Hint] = []
        for hint in meaning {
            if picked.count == 2 { break }
            if picked.contains(where: { Self.hintsOverlap($0.text, hint.text) }) { continue }
            picked.append(hint)
        }
        if picked.isEmpty {
            picked = [Hint(kind: .definition, text: generated.definitionHint)]
        }

        picked.append(Hint(kind: .spelling, text: generated.spellingHint))
        return picked
    }

    /// Whether two clue texts say essentially the same thing (one contains the
    /// other, or they share most of their words), so we avoid repeating content.
    static func hintsOverlap(_ a: String, _ b: String) -> Bool {
        let na = normalizedClue(a), nb = normalizedClue(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na.contains(nb) || nb.contains(na) { return true }
        let ta = Set(na.split(separator: " ")), tb = Set(nb.split(separator: " "))
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let shared = ta.intersection(tb).count
        return Double(shared) / Double(Swift.min(ta.count, tb.count)) >= 0.7
    }

    private static func normalizedClue(_ text: String) -> String {
        let lowered = text.lowercased()
        let kept = lowered.unicodeScalars.map { CharacterSet.lowercaseLetters.contains($0) || $0 == " " ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    static func mask(_ word: String) -> String {
        String(repeating: "•  ", count: word.count).trimmingCharacters(in: .whitespaces)
    }

    static func spellOut(_ word: String) -> String {
        "spelled " + word.uppercased().map(String.init).joined(separator: ", ")
    }
}
