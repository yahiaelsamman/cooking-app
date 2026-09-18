import SwiftUI

/// One highlighted stop in a screen's interactive walkthrough. `targetID` matches the id passed
/// to `.tourAnchor(_:)` on the real control being explained, and is what `AppTour.notify` checks
/// against — `nil` for a step that isn't about one specific control (shown with its own "Next"
/// button instead of waiting on a tap that has nowhere singular to land).
struct TourStep: Identifiable {
    let id: String
    let targetID: String?
    let title: String
    let message: String

    /// A step with no single control to point at — dismissed by its own "Next"/"Got it" button.
    init(id: String, title: String, message: String) {
        self.id = id
        self.targetID = nil
        self.title = title
        self.message = message
    }

    /// A step that highlights a real control — dismissed only by actually using it. Nothing here
    /// blocks the tap from reaching that control; see `TourSpotlight`'s doc comment for why.
    init(target id: String, title: String, message: String) {
        self.id = id
        self.targetID = id
        self.title = title
        self.message = message
    }
}

/// Drives one screen's interactive walkthrough: a queue of `TourStep`s shown one at a time, each
/// advanced either by its own "Next" button (informational steps) or by `notify` being called
/// from the real control it points at — that control's own `Button` action or an `.onChange` on
/// the state it edits, never a gesture bolted onto the overlay itself (see `TourSpotlight`).
///
/// One instance per screen (`@State private var tour = AppTour()`), not shared across screens —
/// each screen's walkthrough starts fresh and is independently gated by its own `@AppStorage`
/// "have I seen this screen's tour" flag, the same one-shot pattern the app already used for the
/// very first coach mark this was built out from.
///
/// `@MainActor`: view-only state, driven entirely by SwiftUI (same pattern as
/// `CookingSessionViewModel`/`PeerSyncService`/etc. in CookingAppCore, lower stakes here since
/// nothing here touches networking or persistence).
@Observable
@MainActor
final class AppTour {
    private(set) var steps: [TourStep] = []
    private(set) var currentIndex = 0

    var currentStep: TourStep? {
        steps.indices.contains(currentIndex) ? steps[currentIndex] : nil
    }

    var isActive: Bool { currentStep != nil }

    func begin(_ steps: [TourStep]) {
        self.steps = steps
        currentIndex = 0
    }

    /// Called from a real control's own action/`.onChange` — advances only if `id` is actually
    /// what the current step is waiting on, so a tap on some other control (or a stale callback
    /// from a step already moved past) is silently ignored rather than skipping steps.
    func notify(_ id: String) {
        guard currentStep?.targetID == id else { return }
        currentIndex += 1
    }

    /// The current step's own "Next"/"Got it" button — only ever wired to an informational step
    /// (`targetID == nil`), but harmless to call otherwise.
    func advanceManually() {
        currentIndex += 1
    }

    func skip() {
        steps = []
        currentIndex = 0
    }
}
