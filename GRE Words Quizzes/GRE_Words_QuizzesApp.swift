//
//  GRE_Words_QuizzesApp.swift
//  GRE Words Quizzes
//
//  Created by Minghao Wang on 6/9/26.
//

import SwiftUI
import CoreData

@main
struct GRE_Words_QuizzesApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

/// Shows the randomized splash screen on launch, then fades into the main app.
struct RootView: View {
    @State private var showSplash = !UserDefaults.standard.bool(forKey: "skipSplash")

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            withAnimation(.easeInOut(duration: 0.6)) {
                showSplash = false
            }
        }
    }
}
