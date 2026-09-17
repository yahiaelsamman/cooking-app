import SwiftUI
import CookingAppCore

/// A step's illustration during cooking: a real bundled illustration when `step.stepImageName` is
/// set, else the same `PlaceholderPhotoView` SF Symbol stand-in used everywhere nothing real
/// exists yet — same fallback pattern as `RecipeHeroImageView`. Sized entirely by whatever frame
/// the caller applies, same as `PlaceholderPhotoView` — this view has no intrinsic size of its own.
struct StepIllustrationView: View {
    let step: RecipeStep
    var tint: Color = .accentColor

    var body: some View {
        if let stepImageName = step.stepImageName {
            Image(stepImageName)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        } else {
            PlaceholderPhotoView(systemImage: step.imageSystemName, tint: tint)
        }
    }
}
