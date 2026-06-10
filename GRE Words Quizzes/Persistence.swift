//
//  Persistence.swift
//  GRE Words Quizzes
//
//  Core Data stack plus first-launch seeding of the local GRE word bank
//  (11,000+ words). The full bank is seeded on a background context in
//  batches so app launch is never blocked.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for entry in WordBank.previewEntries() {
            let word = GREWord(context: viewContext)
            word.word = entry.word
            word.partOfSpeech = entry.partOfSpeech
            word.definition = entry.definition
            word.characteristic = entry.characteristic
            word.highFrequency = entry.highFrequency ?? false
            word.priority = Int16(entry.priority ?? 3)
            word.frequencyRank = Int32(entry.frequencyRank ?? 9_999_999)
            word.synonyms = entry.synonyms
            word.antonyms = entry.antonyms
            word.addedAt = Date()
        }
        try? viewContext.save()
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GRE_Words_Quizzes")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        if !inMemory {
            seedIfNeeded()
            enrichHighFrequencyIfNeeded()
            enrichSynonymsIfNeeded()
        }
    }

    /// Backfills synonyms / antonyms onto words seeded by an earlier version
    /// (store populated before the synonym/antonym hint type existed). No-op
    /// once any word already has the data.
    private func enrichSynonymsIfNeeded() {
        let countRequest = NSFetchRequest<NSNumber>(entityName: "GREWord")
        countRequest.resultType = .countResultType
        let total = (try? container.viewContext.count(for: countRequest)) ?? 0
        guard total > 0 else { return }

        let synRequest = NSFetchRequest<NSNumber>(entityName: "GREWord")
        synRequest.resultType = .countResultType
        synRequest.predicate = NSPredicate(format: "synonyms != nil OR antonyms != nil")
        let synCount = (try? container.viewContext.count(for: synRequest)) ?? 0
        guard synCount == 0 else { return }

        let map = Dictionary(WordBank.load().map { ($0.word, $0) }, uniquingKeysWith: { a, _ in a })
        guard map.values.contains(where: { $0.synonyms != nil || $0.antonyms != nil }) else { return }

        container.performBackgroundTask { context in
            let request = NSFetchRequest<GREWord>(entityName: "GREWord")
            guard let all = try? context.fetch(request) else { return }
            for (index, word) in all.enumerated() {
                if let key = word.word, let entry = map[key] {
                    word.synonyms = entry.synonyms
                    word.antonyms = entry.antonyms
                }
                if (index + 1) % 2_000 == 0 { try? context.save() }
            }
            try? context.save()
        }
    }

    /// Backfills the high-frequency / priority data onto words that were seeded
    /// by an earlier version (store already populated, but no high-frequency
    /// flags yet). Cheap no-op once the data is present.
    private func enrichHighFrequencyIfNeeded() {
        let countRequest = NSFetchRequest<NSNumber>(entityName: "GREWord")
        countRequest.resultType = .countResultType
        let total = (try? container.viewContext.count(for: countRequest)) ?? 0
        guard total > 0 else { return }   // empty store is handled by seeding

        let hfRequest = NSFetchRequest<NSNumber>(entityName: "GREWord")
        hfRequest.resultType = .countResultType
        hfRequest.predicate = NSPredicate(format: "highFrequency == YES")
        let hfCount = (try? container.viewContext.count(for: hfRequest)) ?? 0
        guard hfCount == 0 else { return }

        let map = Dictionary(WordBank.load().map { ($0.word, $0) }, uniquingKeysWith: { a, _ in a })
        guard !map.isEmpty else { return }

        container.performBackgroundTask { context in
            let request = NSFetchRequest<GREWord>(entityName: "GREWord")
            guard let all = try? context.fetch(request) else { return }
            for (index, word) in all.enumerated() {
                if let key = word.word, let entry = map[key] {
                    word.highFrequency = entry.highFrequency ?? false
                    word.priority = Int16(entry.priority ?? 3)
                    word.frequencyRank = Int32(entry.frequencyRank ?? 9_999_999)
                }
                if (index + 1) % 2_000 == 0 { try? context.save() }
            }
            try? context.save()
        }
    }

    /// Seeds the full word bank the first time the app runs (store empty).
    /// Runs on a background context in batches; the view context auto-merges
    /// the inserts so lists populate live without blocking the UI.
    private func seedIfNeeded() {
        let request = NSFetchRequest<NSNumber>(entityName: "GREWord")
        request.resultType = .countResultType
        let existing = (try? container.viewContext.count(for: request)) ?? 0
        guard existing == 0 else { return }

        let entries = WordBank.load()

        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            let now = Date()
            let batchSize = 1_000

            for (index, entry) in entries.enumerated() {
                let word = GREWord(context: context)
                word.word = entry.word
                word.partOfSpeech = entry.partOfSpeech.isEmpty ? nil : entry.partOfSpeech
                word.definition = entry.definition
                word.characteristic = entry.characteristic.isEmpty ? nil : entry.characteristic
                word.frequencyRank = Int32(entry.frequencyRank ?? 9_999_999)
                word.priority = Int16(entry.priority ?? 3)
                word.highFrequency = entry.highFrequency ?? false
                word.synonyms = entry.synonyms
                word.antonyms = entry.antonyms
                word.hintsGenerated = false
                word.timesSeen = 0
                word.timesCorrect = 0
                word.addedAt = now

                if (index + 1) % batchSize == 0 {
                    try? context.save()
                    context.reset()
                }
            }
            try? context.save()
        }
    }
}
