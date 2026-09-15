import SwiftUI

/// A stand-in for real step/recipe photography — a soft gradient "photo card" with the SF Symbol
/// shown large and faint on top, so the sizing/corner-radius/shadow treatment of a real photo can
/// be previewed before any actual images exist. Not a real asset pipeline (see instructions.md):
/// swapping in real photos later just means replacing this view's contents for the ones you have.
struct PlaceholderPhotoView: View {
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.55), tint.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
            }
            .shadow(color: tint.opacity(0.25), radius: 8, y: 4)
    }
}
