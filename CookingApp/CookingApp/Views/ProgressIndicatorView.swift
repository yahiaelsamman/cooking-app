import SwiftUI

struct ProgressIndicatorView: View {
    let progressText: String
    let fraction: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(progressText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ProgressView(value: fraction)
                .tint(.accentColor)
        }
        .padding(.horizontal)
    }
}
