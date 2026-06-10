//
//  ContentView.swift
//  GRE Words Quizzes
//
//  Root tab layout: spoken Practice on one tab, the Word Bank on the other.
//

import SwiftUI
import CoreData

struct ContentView: View {
    // Allows launching directly into a tab for screenshots (`-startTab N`).
    @State private var selection = UserDefaults.standard.integer(forKey: "startTab")

    var body: some View {
        TabView(selection: $selection) {
            QuizView()
                .tag(0)
                .tabItem {
                    Label("Practice", systemImage: "waveform.and.mic")
                }
            ReviewView()
                .tag(1)
                .tabItem {
                    Label("Review", systemImage: "brain.head.profile")
                }
            ProgressDashboardView()
                .tag(2)
                .tabItem {
                    Label("Progress", systemImage: "calendar")
                }
            WordListView()
                .tag(3)
                .tabItem {
                    Label("Word Bank", systemImage: "character.book.closed")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
