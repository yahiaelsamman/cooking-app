import SwiftUI
import CookingAppCore

/// The recipe's photo wherever a full-size hero image is shown (the list cards and
/// `RecipeDetailView`'s header): a real bundled photo when `recipe.heroImageName` is set, else
/// the same gradient placeholder card used everywhere nothing real exists yet. Sized entirely by
/// whatever frame the caller applies, same as `PlaceholderPhotoView` — this view has no intrinsic
/// size of its own.
struct RecipeHeroImageView: View {
    let recipe: Recipe

    var body: some View {
        if let heroImageName = recipe.heroImageName {
            RoundedPhoto(imageName: heroImageName)
        } else {
            PlaceholderPhotoView(systemImage: recipe.iconSystemName)
        }
    }
}

/// A bundled photo that fills whatever frame it's given, cropped to rounded corners. The image is
/// laid over a `Color.clear` that takes the caller's frame, so the rounded clip applies to that
/// frame rather than to the larger `scaledToFill` image (which a caller's `.clipped()` would then
/// cut back to square corners).
struct RoundedPhoto: View {
    let imageName: String

    var body: some View {
        Color.clear
            .overlay {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
