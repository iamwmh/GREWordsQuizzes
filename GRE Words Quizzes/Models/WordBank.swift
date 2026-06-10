//
//  WordBank.swift
//  GRE Words Quizzes
//
//  Loads the large bundled GRE word bank (GREWordBank.json, 11,000+ entries
//  with definitions) that ships inside the app. Falls back to the small
//  curated `SeedWords` list if the resource is missing.
//

import Foundation

/// One decoded entry from the bundled word-bank JSON.
struct BankEntry: Decodable {
    let word: String
    let partOfSpeech: String
    let definition: String
    let characteristic: String
    /// General-usage frequency rank (lower = more common). Used for ordering.
    let frequencyRank: Int?
    /// GRE-list authority tier: 0 = high-frequency core, 1 = common GRE,
    /// 2 = other GRE lists, 3 = supplementary vocabulary.
    let priority: Int?
    /// True for commonly-tested, high-frequency GRE words.
    let highFrequency: Bool?
    /// Comma-separated synonyms (from WordNet), used for the synonym hint type.
    let synonyms: String?
    /// Comma-separated antonyms (from WordNet), used for the antonym hint type.
    let antonyms: String?
}

enum WordBank {
    /// Loads every entry from the bundled JSON, or returns the curated fallback.
    static func load() -> [BankEntry] {
        if let url = Bundle.main.url(forResource: "GREWordBank", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([BankEntry].self, from: data),
           !entries.isEmpty {
            return entries
        }
        return SeedWords.all.map {
            BankEntry(word: $0.word,
                      partOfSpeech: $0.partOfSpeech,
                      definition: $0.definition,
                      characteristic: $0.characteristic,
                      frequencyRank: nil,
                      priority: 0,
                      highFrequency: true,
                      synonyms: nil,
                      antonyms: nil)
        }
    }

    /// A small subset for SwiftUI previews and in-memory stores.
    static func previewEntries(_ limit: Int = 12) -> [BankEntry] {
        SeedWords.all.prefix(limit).map {
            BankEntry(word: $0.word,
                      partOfSpeech: $0.partOfSpeech,
                      definition: $0.definition,
                      characteristic: $0.characteristic,
                      frequencyRank: nil,
                      priority: 0,
                      highFrequency: true,
                      synonyms: nil,
                      antonyms: nil)
        }
    }
}
