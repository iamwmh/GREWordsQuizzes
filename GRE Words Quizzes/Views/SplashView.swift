//
//  SplashView.swift
//  GRE Words Quizzes
//
//  A launch splash that re-randomizes on every appearance: a random solid
//  background color with a scatter of GRE words at varying sizes, positions,
//  rotations, and opacities arranged around the centered app title.
//

import SwiftUI

struct SplashView: View {
    /// One floating word in the background scatter.
    private struct FloatingWord: Identifiable {
        let id = UUID()
        let text: String
        let position: CGPoint
        let fontSize: CGFloat
        let opacity: Double
        let rotation: Double
    }

    @State private var backgroundColor: Color = .blue
    @State private var words: [FloatingWord] = []
    @State private var titleVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                // Scattered GRE words.
                ForEach(words) { word in
                    Text(word.text)
                        .font(.system(size: word.fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(word.opacity))
                        .rotationEffect(.degrees(word.rotation))
                        .position(word.position)
                        .allowsHitTesting(false)
                }

                // Centered title.
                VStack(spacing: 6) {
                    Text("GRE")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                    Text("Words Quizzes")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("Listen · Speak · Remember")
                        .font(.footnote)
                        .opacity(0.85)
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 26)
                .padding(.horizontal, 34)
                .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: 26))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                .scaleEffect(titleVisible ? 1 : 0.85)
                .opacity(titleVisible ? 1 : 0)
            }
            .onAppear {
                randomize(in: geo.size)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    titleVisible = true
                }
            }
        }
    }

    private func randomize(in size: CGSize) {
        backgroundColor = Self.randomColor()

        let pool = SeedWords.all.map(\.word).shuffled()
        let count = min(16, pool.count)

        // Keep a clear band around the centered title.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let clearRadiusX = size.width * 0.42
        let clearRadiusY: CGFloat = 130

        var result: [FloatingWord] = []
        var attempts = 0
        while result.count < count && attempts < count * 12 {
            attempts += 1
            let x = CGFloat.random(in: 0.05...0.95) * size.width
            let y = CGFloat.random(in: 0.06...0.94) * size.height
            // Skip points that fall inside the title's clear zone.
            if abs(x - center.x) < clearRadiusX && abs(y - center.y) < clearRadiusY {
                continue
            }
            let word = pool[result.count]
            result.append(FloatingWord(
                text: word,
                position: CGPoint(x: x, y: y),
                fontSize: CGFloat.random(in: 15...40),
                opacity: Double.random(in: 0.18...0.55),
                rotation: Double.random(in: -18...18)
            ))
        }
        words = result
    }

    private static func randomColor() -> Color {
        Color(hue: Double.random(in: 0...1),
              saturation: Double.random(in: 0.45...0.7),
              brightness: Double.random(in: 0.5...0.78))
    }
}

#Preview {
    SplashView()
}
