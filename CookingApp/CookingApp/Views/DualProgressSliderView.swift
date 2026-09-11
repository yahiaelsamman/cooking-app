import SwiftUI

/// Shows both people's progress on one shared track, each as a fraction of their own (possibly
/// different-length) track — so the relative positions are directly comparable, and you can see
/// at a glance whether you or your partner is further along, not just what step they're on.
struct DualProgressSliderView: View {
    let myFraction: Double
    let partnerFraction: Double?

    private let markerSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(geo.size.width - markerSize, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)

                marker(color: .accentColor, systemImage: "person.fill")
                    .offset(x: usableWidth * myFraction)

                if let partnerFraction {
                    marker(color: .orange, systemImage: "person.fill")
                        .offset(x: usableWidth * partnerFraction)
                }
            }
        }
        .frame(height: markerSize)
    }

    private func marker(color: Color, systemImage: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: markerSize, height: markerSize)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
            }
    }
}
