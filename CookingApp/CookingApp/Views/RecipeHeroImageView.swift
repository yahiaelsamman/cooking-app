import SwiftUI
import CookingAppCore

/// The recipe's photo wherever a full-size hero image is shown (currently just
/// `RecipeDetailView`'s header): a real bundled photo when `recipe.heroImageName` is set, else
/// the same gradient placeholder card used everywhere nothing real exists yet. Sized entirely by
/// whatever frame the caller applies, same as `PlaceholderPhotoView` — this view has no intrinsic
/// size of its own.
struct RecipeHeroImageView: View {
    let recipe: Recipe

    var body: some View {
        if let heroImageName = recipe.heroImageName {
            Image(heroImageName)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        } else {
            PlaceholderPhotoView(systemImage: recipe.iconSystemName)
        }
    }
}
