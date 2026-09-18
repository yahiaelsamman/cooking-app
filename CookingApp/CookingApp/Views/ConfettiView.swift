import SwiftUI

/// A brief, one-shot confetti burst — purely decorative, plays once on appear and settles. Used
/// on `StepView`'s completion screen as the "dopamine" moment for finishing a recipe.
struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var animate = false

    private struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let xOffset: CGFloat
        let yOffset: CGFloat
        let rotation: Double
        let size: CGFloat
    }

    // Drawn from the hand-drawn illustration system's locked, desaturated palette
    // (`illustrations/prompts/*.md`) rather than generic saturated system colors — this is the
    // app's biggest "juice" moment, and it should read as the same restrained, hand-drawn app as
    // everywhere else, not a different, louder one.
    private static let colors: [Color] = [
        Color(red: 0.9765, green: 0.9490, blue: 0.8392), // lighter cream #F9F2D6
        Color(red: 0.9412, green: 0.8314, blue: 0.4549), // stronger food yellow (egg yolk) #F0D474
        Color(red: 0.7686, green: 0.3412, blue: 0.2392), // muted tomato red #C4573D
        Color(red: 0.5412, green: 0.6039, blue: 0.3569), // muted herb green #8A9A5B
        Color(red: 0.6392, green: 0.5647, blue: 0.4078), // muted beige/brown #A39068
    ]

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 1.8)
                    .rotationEffect(.degrees(animate ? piece.rotation : 0))
                    .offset(x: animate ? piece.xOffset : 0, y: animate ? piece.yOffset : 0)
                    .opacity(animate ? 0 : 1)
            }
        }
        // Purely decorative — nothing here is meant to be read or interacted with, so it should
        // never take VoiceOver focus away from the completion message.
        .accessibilityHidden(true)
        .onAppear {
            // Motion-sensitive users get the haptic/checkmark/text celebration in
            // `StepView.completionView` still — just not a screen full of moving pieces.
            guard !reduceMotion else { return }
            pieces = (0..<24).map { _ in
                Piece(
                    color: Self.colors.randomElement()!,
                    xOffset: CGFloat.random(in: -170...170),
                    yOffset: CGFloat.random(in: -280 ... -40),
                    rotation: Double.random(in: 180...720),
                    size: CGFloat.random(in: 6...10)
                )
            }
            withAnimation(.easeOut(duration: 1.1)) {
                animate = true
            }
        }
    }
}
