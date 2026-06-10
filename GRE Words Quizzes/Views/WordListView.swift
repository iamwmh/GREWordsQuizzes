//
//  WordListView.swift
//  GRE Words Quizzes
//
//  Browse the local GRE word bank, inspect each word's three generated hints,
//  review study stats, and add new words to the bank.
//

import SwiftUI
import CoreData

struct WordListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \GREWord.word, ascending: true)],
        animation: .default)
    private var words: FetchedResults<GREWord>

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var filter: WordFilter = .all

    enum WordFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case highFrequency = "High-frequency"
        var id: String { rawValue }
    }

    private var highFrequencyCount: Int {
        words.reduce(0) { $0 + ($1.highFrequency ? 1 : 0) }
    }

    private var filtered: [GREWord] {
        var list = Array(words)
        if filter == .highFrequency {
            list = list.filter { $0.highFrequency }
        }
        if !searchText.isEmpty {
            list = list.filter {
                ($0.word ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.definition ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(WordFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }

                Section {
                    ForEach(filtered) { word in
                        NavigationLink {
                            WordDetailView(word: word)
                        } label: {
                            WordRow(word: word)
                        }
                    }
                    .onDelete(perform: deleteWords)
                } header: {
                    Text("\(filtered.count) words · ⭐︎ \(highFrequencyCount) high-frequency")
                }
            }
            .searchable(text: $searchText, prompt: "Search words or meanings")
            .navigationTitle("Word Bank")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddWordView()
            }
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        let target = filtered
        for index in offsets {
            viewContext.delete(target[index])
        }
        try? viewContext.save()
    }
}

private struct WordRow: View {
    @ObservedObject var word: GREWord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if word.highFrequency {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(word.word ?? "—")
                    .font(.headline)
                if let pos = word.partOfSpeech, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemGray6), in: Capsule())
                }
                Spacer()
                if word.timesSeen > 0 {
                    Text("\(word.timesCorrect)/\(word.timesSeen)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(word.timesCorrect == word.timesSeen ? .green : .secondary)
                }
            }
            Text(word.definition ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

struct WordDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var word: GREWord

    @State private var hints: GeneratedHints?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Text(word.definition ?? "")
                if let pos = word.partOfSpeech, !pos.isEmpty {
                    LabeledContent("Part of speech", value: pos)
                }
                if word.highFrequency {
                    Label("High-frequency · commonly tested", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Meaning")
            }

            Section {
                if let c = word.characteristic, !c.isEmpty {
                    Text(c)
                }
            } header: {
                Text("Characteristics")
            }

            if (word.synonyms?.isEmpty == false) || (word.antonyms?.isEmpty == false) {
                Section {
                    if let s = word.synonyms, !s.isEmpty {
                        LabeledContent("Synonyms", value: s)
                    }
                    if let a = word.antonyms, !a.isEmpty {
                        LabeledContent("Antonyms", value: a)
                    }
                } header: {
                    Text("Related words")
                }
            }

            Section {
                if let hints {
                    let all = hints.allHints
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, hint in
                        hintRow(number: index + 1, title: hint.kind.rawValue, text: hint.text)
                    }
                } else if isLoading {
                    HStack { ProgressView(); Text("Generating hints…") }
                } else {
                    Text("Tap below to generate the quiz hints.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await regenerate() }
                } label: {
                    Label(hints == nil ? "Generate hints" : "Regenerate hints",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isLoading)
            } header: {
                Text("Quiz hints")
            } footer: {
                Text("Each round mixes the meaning, characteristic, and (when available) a synonym or antonym clue at random, then ends with the spelling.")
            }

            Section {
                LabeledContent("Times seen", value: "\(word.timesSeen)")
                LabeledContent("Times correct", value: "\(word.timesCorrect)")
                if let last = word.lastReviewed {
                    LabeledContent("Last reviewed", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Progress")
            }
        }
        .navigationTitle(word.word ?? "Word")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if hints == nil {
                isLoading = true
                hints = await HintGenerator.shared.hints(for: word, context: viewContext)
                isLoading = false
            }
        }
    }

    private func hintRow(number: Int, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hint \(number) · \(title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
        }
        .padding(.vertical, 2)
    }

    private func regenerate() async {
        isLoading = true
        hints = await HintGenerator.shared.regenerate(for: word, context: viewContext)
        isLoading = false
    }
}

struct AddWordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var word = ""
    @State private var partOfSpeech = ""
    @State private var definition = ""
    @State private var characteristic = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("e.g. ephemeral", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Part of speech (optional)", text: $partOfSpeech)
                }
                Section("Definition") {
                    TextField("Meaning of the word", text: $definition, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Characteristics (optional)") {
                    TextField("Features, use, color, shape, feeling…", text: $characteristic, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  definition.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let item = GREWord(context: viewContext)
        item.word = word.trimmingCharacters(in: .whitespaces).lowercased()
        item.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespaces)
        item.definition = definition.trimmingCharacters(in: .whitespaces)
        item.characteristic = characteristic.trimmingCharacters(in: .whitespaces)
        item.hintsGenerated = false
        item.timesSeen = 0
        item.timesCorrect = 0
        item.addedAt = Date()
        try? viewContext.save()
        dismiss()
    }
}

#Preview {
    WordListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
