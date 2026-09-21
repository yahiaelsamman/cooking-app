import Foundation
import Testing
@testable import CookingAppCore

/// Timers are measured against real end dates, not counted in one-second ticks: the ticker stops
/// whenever iOS suspends the app, so a tick count falls behind real time. These tests move a fake
/// clock forward without any real waiting.
@MainActor
struct TimerClockTests {

    private func session(startingAt start: Date) -> (CookingSessionViewModel, RecipeStep, Box) {
        let recipe = SampleRecipes.searedSteak
        let step = recipe.soloSteps.first { $0.timerSeconds == 360 }!
        let clock = Box(start)
        let session = CookingSessionViewModel(recipe: recipe)
        session.nowProvider = { clock.now }
        return (session, step, clock)
    }

    final class Box: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    @Test func remainingTimeFollowsTheClockNotTheTickCount() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let (session, step, clock) = session(startingAt: start)

        session.startTimer(for: step)
        // The app is suspended for 2 minutes: no ticks happen, but the clock moves on.
        clock.now = start.addingTimeInterval(120)
        session.refreshTimers()

        #expect(session.activeTimer(for: step)?.remainingSeconds == 240)
        session.cancelTimer(for: step)
    }

    @Test func aTimerThatRanOutWhileAwayFinishesOnceWhenRefreshed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let (session, step, clock) = session(startingAt: start)
        var finishedSteps: [UUID] = []
        session.onTimerFinished = { finishedSteps.append($0.id) }

        session.startTimer(for: step)
        clock.now = start.addingTimeInterval(400) // 40s past the end
        session.refreshTimers()
        session.refreshTimers() // a second refresh must not fire it again

        #expect(session.activeTimer(for: step) == nil)
        #expect(finishedSteps == [step.id])
    }

    @Test func restartingATimerResetsItsEndDate() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let (session, step, clock) = session(startingAt: start)

        session.startTimer(for: step)
        clock.now = start.addingTimeInterval(100)
        session.startTimer(for: step)
        session.refreshTimers()

        #expect(session.activeTimer(for: step)?.remainingSeconds == 360)
        session.cancelTimer(for: step)
    }

    @Test func rescheduleRegistersEachRunningTimerWithItsRemainingTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let (session, step, clock) = session(startingAt: start)
        var scheduled: [(UUID, Int)] = []

        session.startTimer(for: step)
        session.onTimerScheduled = { scheduled.append(($0.id, $1)) }
        clock.now = start.addingTimeInterval(60)
        session.refreshTimers()
        session.rescheduleTimerNotifications()

        #expect(scheduled.count == 1)
        #expect(scheduled.first?.0 == step.id)
        #expect(scheduled.first?.1 == 300)
        session.cancelTimer(for: step)
    }

    @Test func aPersistedTimerKeepsItsOriginalEndDate() {
        let recipe = SampleRecipes.searedSteak
        let step = recipe.soloSteps.first { $0.timerSeconds == 360 }!
        let end = Date().addingTimeInterval(200)
        let timer = ActiveTimer(step: step, totalSeconds: 360, remainingSeconds: 200, endDate: end)
        #expect(timer.endDate == end)
    }
}
