import Foundation
import SwiftData
import Testing
@testable import CookingAppCore

/// Covers the force-quit persistence layer: `SessionPersistence`'s raw save/load/clear contract,
/// and `ActiveSessionStore`'s use of it (persisting solo sessions on every mutation, never
/// persisting two-person ones, and rebuilding a live session from a snapshot on `restoreIfNeeded`).
///
/// `.serialized`, matching `RecipeSeederTests`'s convention — every test here reads/writes the
/// same `SessionPersistence` key (backed by `UserDefaults.standard`), which would race under
/// swift-testing's default parallel execution.
///
/// `@MainActor`: `ActiveSessionStore`/`CookingSessionViewModel` are both `@MainActor` (see their
/// doc comments), so every call below needs to run on the main actor too.
@Suite(.serialized)
@MainActor
struct SessionPersistenceTests {

    init() {
        SessionPersistence.clear()
    }

    private func makeInMemoryContext(inserting recipe: Recipe? = nil) throws -> ModelContext {
        let schema = Schema([Recipe.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        if let recipe {
            context.insert(recipe)
            try context.save()
        }
        return context
    }

    private func makeTestRecipe(timerSeconds: Int? = 60) -> Recipe {
        Recipe(
            title: "Persistence Test Recipe",
            summary: "A recipe used only to test session persistence.",
            soloSteps: [
                RecipeStep(order: 0, instruction: "Step one.", assignee: .solo, imageSystemName: "star"),
                RecipeStep(order: 1, instruction: "Step two.", assignee: .solo, timerSeconds: timerSeconds, imageSystemName: "timer"),
                RecipeStep(order: 2, instruction: "Step three.", assignee: .solo, imageSystemName: "checkmark")
            ],
            iconSystemName: "star",
            difficulty: 1,
            soloCookTimeMinutes: 5,
            ingredients: [Ingredient(name: "Thing", amount: "1")]
        )
    }

    // MARK: - SessionPersistence

    @Test func saveLoadClearRoundTrip() {
        #expect(SessionPersistence.load() == nil)

        let snapshot = CookingSessionSnapshot(
            recipeID: UUID(),
            role: nil,
            currentIndex: 2,
            timers: [TimerSnapshot(stepID: UUID(), totalSeconds: 60, endDate: Date().addingTimeInterval(30))]
        )
        SessionPersistence.save(snapshot)

        #expect(SessionPersistence.load() == snapshot)

        SessionPersistence.clear()
        #expect(SessionPersistence.load() == nil)
    }

    // MARK: - ActiveSessionStore.setActive persisting (solo only)

    @Test func setActivePersistsASoloSessionImmediately() throws {
        let recipe = makeTestRecipe()
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: recipe)

        store.setActive(session)

        let snapshot = SessionPersistence.load()
        #expect(snapshot?.recipeID == recipe.id)
        #expect(snapshot?.role == nil)
        #expect(snapshot?.currentIndex == 0)
    }

    @Test func setActiveDoesNotPersistATwoPersonSession() {
        let recipe = SampleRecipes.pastaForTwo
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: recipe, role: .personA)

        store.setActive(session)

        #expect(SessionPersistence.load() == nil)
    }

    @Test func advancingASoloSessionUpdatesThePersistedSnapshot() {
        let recipe = makeTestRecipe()
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: recipe)
        store.setActive(session)

        session.advance()

        #expect(SessionPersistence.load()?.currentIndex == 1)
    }

    @Test func completingASoloSessionClearsThePersistedSnapshot() {
        let recipe = makeTestRecipe()
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: recipe)
        store.setActive(session)
        session.advance()
        session.advance()
        #expect(SessionPersistence.load() != nil)

        session.advance()

        #expect(session.isComplete)
        #expect(SessionPersistence.load() == nil)
    }

    @Test func startingATimerUpdatesThePersistedSnapshotWithTimers() {
        let recipe = makeTestRecipe()
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: recipe)
        store.setActive(session)
        let timedStep = session.track.first { $0.timerSeconds != nil }!

        session.startTimer(for: timedStep)

        let snapshot = SessionPersistence.load()
        #expect(snapshot?.timers.count == 1)
        #expect(snapshot?.timers.first?.stepID == timedStep.id)
        #expect(snapshot?.timers.first?.totalSeconds == 60)

        session.cancelTimer(for: timedStep) // avoid leaking a live Timer past the end of the test
        #expect(SessionPersistence.load()?.timers.isEmpty == true)
    }

    @Test func clearRemovesThePersistedSnapshot() {
        let recipe = makeTestRecipe()
        let store = ActiveSessionStore()
        store.setActive(CookingSessionViewModel(recipe: recipe))
        #expect(SessionPersistence.load() != nil)

        store.clear()

        #expect(SessionPersistence.load() == nil)
    }

    // MARK: - ActiveSessionStore.restoreIfNeeded

    @Test func restoreIfNeededDoesNothingWithNoSnapshot() throws {
        let context = try makeInMemoryContext()
        let store = ActiveSessionStore()

        store.restoreIfNeeded(modelContext: context)

        #expect(!store.hasActiveSession)
    }

    @Test func restoreIfNeededClearsAndSkipsASnapshotForARecipeThatNoLongerExists() throws {
        let context = try makeInMemoryContext()
        SessionPersistence.save(CookingSessionSnapshot(recipeID: UUID(), role: nil, currentIndex: 1, timers: []))

        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: context)

        #expect(!store.hasActiveSession)
        #expect(SessionPersistence.load() == nil)
    }

    @Test func restoreIfNeededIgnoresATwoPersonSnapshot() throws {
        // Defensive-only: `setActive` never actually writes one of these (see the test above), but
        // `restoreIfNeeded` should refuse to act on one regardless of how it got there.
        let recipe = makeTestRecipe()
        let context = try makeInMemoryContext(inserting: recipe)
        SessionPersistence.save(CookingSessionSnapshot(recipeID: recipe.id, role: .personA, currentIndex: 0, timers: []))

        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: context)

        #expect(!store.hasActiveSession)
    }

    @Test func restoreIfNeededRebuildsASoloSessionAtTheSavedStepWithLiveTimersRecomputedFromElapsedTime() throws {
        let recipe = makeTestRecipe()
        let context = try makeInMemoryContext(inserting: recipe)
        let timedStep = recipe.track(for: nil)[1]
        SessionPersistence.save(CookingSessionSnapshot(
            recipeID: recipe.id,
            role: nil,
            currentIndex: 1,
            timers: [TimerSnapshot(stepID: timedStep.id, totalSeconds: 60, endDate: Date().addingTimeInterval(50))]
        ))

        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: context)

        #expect(store.hasActiveSession)
        #expect(store.currentSession?.currentIndex == 1)
        let restoredTimer = store.currentSession?.activeTimer(for: timedStep)
        #expect(restoredTimer?.totalSeconds == 60)
        // Recomputed from the (still-in-the-future) endDate, not read back verbatim — allow a
        // couple seconds of slack for however long the test itself took to reach this point.
        #expect((restoredTimer?.remainingSeconds ?? -1) > 45)
        #expect((restoredTimer?.remainingSeconds ?? .max) <= 50)

        store.currentSession?.cancelTimer(for: timedStep) // avoid leaking a live Timer
    }

    @Test func restoreIfNeededDropsATimerThatAlreadyFinishedWhileTheAppWasDead() throws {
        let recipe = makeTestRecipe()
        let context = try makeInMemoryContext(inserting: recipe)
        let timedStep = recipe.track(for: nil)[1]
        SessionPersistence.save(CookingSessionSnapshot(
            recipeID: recipe.id,
            role: nil,
            currentIndex: 1,
            timers: [TimerSnapshot(stepID: timedStep.id, totalSeconds: 60, endDate: Date().addingTimeInterval(-30))]
        ))

        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: context)

        #expect(store.hasActiveSession)
        #expect(store.currentSession?.activeTimers.isEmpty == true)
    }

    @Test func restoreIfNeededDoesNothingIfASessionIsAlreadyActive() throws {
        let recipe = makeTestRecipe()
        let context = try makeInMemoryContext(inserting: recipe)
        SessionPersistence.save(CookingSessionSnapshot(recipeID: recipe.id, role: nil, currentIndex: 2, timers: []))

        let store = ActiveSessionStore()
        let alreadyActive = CookingSessionViewModel(recipe: recipe)
        store.setActive(alreadyActive) // this itself overwrites the snapshot, but the guard is what's under test

        store.restoreIfNeeded(modelContext: context)

        #expect(store.currentSession === alreadyActive)
    }

    @Test func savedTimerStepIDStillResolvesAfterBundledContentIsReseeded() throws {
        let recipe = makeTestRecipe()
        let context = try makeInMemoryContext(inserting: recipe)
        let timedStep = recipe.track(for: nil)[1]
        SessionPersistence.save(CookingSessionSnapshot(
            recipeID: recipe.id,
            role: nil,
            currentIndex: 1,
            timers: [TimerSnapshot(stepID: timedStep.id, totalSeconds: 60, endDate: Date().addingTimeInterval(50))]
        ))

        // A relaunch re-seeds with freshly built steps (new random UUIDs) carrying the same content.
        let reseeded = makeTestRecipe()
        #expect(reseeded.soloSteps[1].id != timedStep.id)
        recipe.updateBundledContent(from: reseeded)
        #expect(recipe.soloSteps[1].id == timedStep.id)
        #expect(recipe.soloSteps.map(\.instruction) == reseeded.soloSteps.map(\.instruction))

        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: context)
        let restored = store.currentSession?.activeTimer(for: recipe.track(for: nil)[1])
        #expect(restored != nil)
        store.currentSession?.cancelTimer(for: recipe.track(for: nil)[1])
    }
}
