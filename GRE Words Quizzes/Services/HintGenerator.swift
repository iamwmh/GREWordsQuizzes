//
//  HintGenerator.swift
//  GRE Words Quizzes
//
//  Produces three hints from three different dimensions for a GRE word:
//    1. Definition / meaning hint
//    2. Spelling hint (the first two letters)
//    3. Characteristic hint (features, use, color, shape, connotation)
//
//  When Apple Intelligence (the on-device Foundation model) is available the
//  definition and characteristic hints are rewritten into fresh, spoken-
//  friendly clues that never reveal the target word. When it is not available
//  the curated seed data is used directly so the app always works offline.
//

import Foundation
import CoreData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A typed, labeled clue for one hint dimension.
struct Hint: Equatable, Identifiable {
    enum Kind: String {
        case definition = "Definition"
        case spelling = "Spelling"
        case characteristic = "Characteristics"
        case synonym = "Synonym"
        case antonym = "Antonym"
    }
    let id = UUID()
    let kind: Kind
    let text: String

    static func == (lhs: Hint, rhs: Hint) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text
    }
}

/// The clues that drive a single quiz round. Definition, spelling, and
/// characteristic are always present; the synonym / antonym clues are present
/// only when the word has that data, so they appear in some rounds and not
/// others, mixed in randomly with the other types.
struct GeneratedHints: Equatable {
    var definitionHint: String
    var spellingHint: String
    /// A distinct characteristic clue. `nil` when the word has no real
    /// characteristic of its own (we never fabricate one from the definition,
    /// which would just duplicate the definition hint).
    var characteristicHint: String?
    var synonymHint: String?
    var antonymHint: String?

    var asArray: [String] { [definitionHint, spellingHint, characteristicHint].compactMap { $0 } }

    /// Every available typed clue for this word.
    var allHints: [Hint] {
        var hints: [Hint] = [Hint(kind: .definition, text: definitionHint)]
        if let characteristicHint, !characteristicHint.isEmpty {
            hints.append(Hint(kind: .characteristic, text: characteristicHint))
        }
        if let synonymHint { hints.append(Hint(kind: .synonym, text: synonymHint)) }
        if let antonymHint { hints.append(Hint(kind: .antonym, text: antonymHint)) }
        hints.append(Hint(kind: .spelling, text: spellingHint))
        return hints
    }
}

#if canImport(FoundationModels)
/// Structured output requested from the on-device model. Spelling is computed
/// locally and deliberately excluded here.
@available(iOS 26.0, *)
@Generable
struct ModelHints {
    @Guide(description: "A clear, spoken one-sentence clue describing the word's meaning. Never spell or say the target word itself.")
    var definitionHint: String

    @Guide(description: "A vivid, concrete one-sentence clue about the thing's features, typical use, color, shape, or feeling. Never spell or say the target word itself.")
    var characteristicHint: String
}
#endif

@MainActor
final class HintGenerator {
    static let shared = HintGenerator()

    private init() {}

    /// Whether the on-device language model is ready to generate hints.
    var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// A short, human-readable status describing model availability for the UI.
    var modelStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Intelligence: on-device hints"
            case .unavailable(.deviceNotEligible):
                return "Curated hints (device not eligible for Apple Intelligence)"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Curated hints (enable Apple Intelligence in Settings)"
            case .unavailable(.modelNotReady):
                return "Curated hints (model still downloading)"
            case .unavailable:
                return "Curated hints (Apple Intelligence unavailable)"
            }
        }
        #endif
        return "Curated hints"
    }

    /// Returns the three hints for a word, generating and caching them in
    /// Core Data on first use.
    func hints(for word: GREWord, context: NSManagedObjectContext) async -> GeneratedHints {
        let spelling = Self.spellingHint(for: word.word ?? "")
        let target = word.word ?? ""
        let synonymHint = Self.synonymHint(from: word.synonyms, word: target)
        let antonymHint = Self.antonymHint(from: word.antonyms, word: target)

        // Use cached hints when we already produced them.
        if word.hintsGenerated, let h1 = word.hint1, !h1.isEmpty {
            return GeneratedHints(definitionHint: h1,
                                  spellingHint: word.hint2?.isEmpty == false ? word.hint2! : spelling,
                                  characteristicHint: word.hint3?.isEmpty == false ? word.hint3 : nil,
                                  synonymHint: synonymHint,
                                  antonymHint: antonymHint)
        }

        let definition = word.definition ?? "This word's meaning is described here."
        // Only use a real, distinct characteristic — never the definition itself.
        let storedCharacteristic = (word.characteristic?.isEmpty == false) ? word.characteristic : nil
        let fallback = GeneratedHints(
            definitionHint: definition,
            spellingHint: spelling,
            characteristicHint: storedCharacteristic,
            synonymHint: synonymHint,
            antonymHint: antonymHint
        )

        var result = fallback

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            if let model = await generateWithModel(word: word.word ?? "",
                                                   definition: word.definition ?? "",
                                                   characteristic: word.characteristic ?? "") {
                result = GeneratedHints(definitionHint: model.definitionHint,
                                        spellingHint: spelling,
                                        characteristicHint: model.characteristicHint,
                                        synonymHint: synonymHint,
                                        antonymHint: antonymHint)
            }
        }
        #endif

        // Cache the result back onto the managed object.
        word.hint1 = result.definitionHint
        word.hint2 = result.spellingHint
        word.hint3 = result.characteristicHint
        word.hintsGenerated = true
        try? context.save()

        return result
    }

    /// Forces regeneration (ignores the cache) — used by a "regenerate" action.
    func regenerate(for word: GREWord, context: NSManagedObjectContext) async -> GeneratedHints {
        word.hintsGenerated = false
        word.hint1 = nil
        word.hint3 = nil
        return await hints(for: word, context: context)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithModel(word: String, definition: String, characteristic: String) async -> ModelHints? {
        let instructions = """
        You are a vocabulary coach writing audio quiz clues for an English learner \
        studying GRE words. You will be given a target word with its meaning. \
        Write clues that help the learner recall the word WITHOUT ever saying, \
        spelling, or using any form of the target word or its root. Keep each \
        clue to a single natural-sounding sentence suitable for text-to-speech.
        """

        let prompt = """
        Target word: "\(word)"
        Meaning: \(definition)
        Known characteristics: \(characteristic)

        Produce two clues for this word:
        1. definitionHint: paraphrase the meaning in fresh words.
        2. characteristicHint: a vivid, concrete image of its features, use, \
        color, shape, or the feeling it evokes.
        Do not reveal the word itself.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: ModelHints.self)
            let content = response.content
            // Guard against the model accidentally leaking the answer.
            if Self.leaksAnswer(content.definitionHint, word: word) ||
                Self.leaksAnswer(content.characteristicHint, word: word) {
                return nil
            }
            return content
        } catch {
            return nil
        }
    }

    private static func leaksAnswer(_ text: String, word: String) -> Bool {
        guard word.count > 3 else { return false }
        let stem = String(word.lowercased().prefix(max(4, word.count - 2)))
        return text.lowercased().contains(stem)
    }
    #endif

    /// Splits a stored comma-separated relation list into clean words, dropping
    /// anything that would give the answer away (same stem as the target).
    static func relationWords(from stored: String?, word: String) -> [String] {
        guard let stored, !stored.isEmpty else { return [] }
        let target = word.lowercased()
        let stem = String(target.prefix(4))
        return stored
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != target && !$0.hasPrefix(stem) }
    }

    /// Joins up to two words into a spoken phrase: "x" or "x or y".
    private static func spokenList(_ words: [String]) -> String {
        let picked = Array(words.prefix(2))
        if picked.count == 2 { return "\(picked[0]) or \(picked[1])" }
        return picked.first ?? ""
    }

    /// Builds a synonym clue ("Close in meaning to …"), or nil if none.
    static func synonymHint(from stored: String?, word: String) -> String? {
        let words = relationWords(from: stored, word: word)
        guard !words.isEmpty else { return nil }
        return "Close in meaning to \(spokenList(words))."
    }

    /// Builds an antonym clue ("Roughly the opposite of …"), or nil if none.
    static func antonymHint(from stored: String?, word: String) -> String? {
        let words = relationWords(from: stored, word: word)
        guard !words.isEmpty else { return nil }
        return "It is roughly the opposite of \(spokenList(words))."
    }

    /// Builds a spoken spelling clue from the first two letters of the word.
    static func spellingHint(for word: String) -> String {
        let letters = Array(word.uppercased())
        guard let first = letters.first else {
            return "No spelling hint is available."
        }
        if letters.count >= 2 {
            return "The word begins with the letters \(first), as in the first letter, and \(letters[1]), as in the second letter."
        }
        return "The word begins with the letter \(first)."
    }
}
