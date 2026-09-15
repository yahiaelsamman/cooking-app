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
                } else {
                    Image(systemName: filled ? "star.fill" : "star")
                }
            }
        }
        .font(interactive ? .title2 : .caption2)
        .foregroundStyle(.yellow)
    }
}
