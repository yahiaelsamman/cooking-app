import SwiftUI

/// A 1...5 star rating control. Interactive on the recipe detail screen (tapping the
/// already-set top star clears the rating back to `nil` rather than getting stuck once set);
/// non-interactive (no tap targets, smaller) wherever it's just a compact readout, like the
/// recipe list row.
struct StarRatingView: View {
    let rating: Int?
    var interactive: Bool = true
    var onSet: ((Int?) -> Void)? = nil

    var body: some View {
        HStack(spacing: interactive ? 6 : 2) {
            ForEach(1...5, id: \.self) { value in
                let filled = (rating ?? 0) >= value
                if interactive {
                    Button {
                        onSet?(rating == value ? nil : value)
                    } label: {
                        Image(systemName: filled ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    // Otherwise every one of the 5 buttons reads as an indistinguishable
                    // "star, button" / "star fill, button" to VoiceOver.
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                } else {
                    Image(systemName: filled ? "star.fill" : "star")
                }
            }
        }
        .font(interactive ? .title2 : .caption2)
        .foregroundStyle(.yellow)
        .modifier(NonInteractiveSummary(isApplied: !interactive, summary: ratingSummary))
    }

    private var ratingSummary: String {
        guard let rating else { return "Not rated" }
        return "Rating: \(rating) out of 5 stars"
    }
}

/// Applied only to the non-interactive display mode — the recipe list row's 5 star images have
/// nothing to individually focus, so they're combined into one clear summary ("Rating: 4 out of 5
/// stars") instead of VoiceOver reading 5 fragmented, indistinguishable "star" images. Left as a
/// no-op for the interactive mode, whose 5 buttons need to stay separately focusable/tappable —
/// combining them would make individual stars unreachable.
private struct NonInteractiveSummary: ViewModifier {
    let isApplied: Bool
    let summary: String

    func body(content: Content) -> some View {
        if isApplied {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(summary)
        } else {
            content
        }
    }
}
