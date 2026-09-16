import SwiftUI
import SwiftData
import UIKit
import CookingAppCore

/// One finished-timer toast — non-blocking (unlike a `.alert`, it never demands a tap before you
/// can keep interacting with the rest of the screen), which matters most when the timer that just
/// finished belongs to a step you've since swiped away from.
private struct TimerFinishedBanner: Identifiable {
    let id = UUID()
    let instruction: String
}

struct StepView: View {
    let session: CookingSessionViewModel
    @Binding var path: NavigationPath
    @Environment(ActiveSessionStore.self) private var sessionStore
    @Environment(\.modelContext) private var modelContext

    @State private var timerFinishedBanners: [TimerFinishedBanner] = []
    @State private var showEndSessionConfirm = false

    /// True once both people have actually finished the recipe — my own last step, and the
    /// partner's, both reached. Detected purely from progress already exchanged (`advance()`
    /// already sends a `progressUpdate` at the completing step), no extra message needed.
    private var bothFinished: Bool {
        session.role != nil && session.isComplete && session.partnerProgressFraction == 1.0
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor.ignoresSafeArea()

            if session.isComplete {
                completionView
            } else {
                activeStepView
            }

            timerFinishedBannerStack
        }
        .navigationBarBackButtonHidden(true)
        .disablesInteractiveSwipeBack()
        .toolbar {
            if session.role != nil && !session.isComplete && session.partnerConnectionState != .idle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End Session", role: .destructive) {
                        showEndSessionConfirm = true
                    }
                    .font(.caption)
                }
            }
        }
        .confirmationDialog(
            "End the shared session?",
            isPresented: $showEndSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                session.endSharedSession()
            }
            Button("Keep Cooking Together", role: .cancel) {}
        } message: {
            Text("Your partner will be disconnected too. You can keep cooking on your own afterward.")
        }
        .onAppear {
            session.onTimerScheduled = { step, duration in
                NotificationScheduler.schedule(step: step, durationSeconds: duration)
            }
            session.onTimerUnscheduled = { step in
                NotificationScheduler.cancel(step: step)
            }
            session.onTimerFinished = { step in
                // Cancel the corresponding notification — we're about to show our own in-app
                // banner, and reaching this callback at all means the app was foregrounded when
                // the timer hit zero, so the notification would just be a redundant duplicate.
                NotificationScheduler.cancel(step: step)
                let banner = TimerFinishedBanner(instruction: step.instruction)
                timerFinishedBanners.append(banner)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    timerFinishedBanners.removeAll { $0.id == banner.id }
                }
            }
            if session.role != nil {
                session.announcePresence(isAway: false)
            }
            // Cooking is a hands-off, glance-at-the-screen activity — messy hands mean a locked
            // screen mid-step is a real interruption, not a minor one. Every mainstream recipe
            // app disables the idle timer for exactly this reason while a step is on screen.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            if session.role != nil {
                session.announcePresence(isAway: true)
            }
            // Restore normal auto-lock the moment cooking isn't the active screen — never leave
            // the device unable to sleep just because it once showed a recipe step.
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: bothFinished) { _, finished in
            guard finished else { return }
            session.endSharedSession()
            sessionStore.clear()
        }
        .onChange(of: session.isComplete) { _, isComplete in
            // My own track reached its end — counts as "I cooked this" regardless of mode, so
            // this fires once whether solo or two-person, independent of `bothFinished` above
            // (which only handles tearing down the shared connection). Going back from the
            // completion screen and finishing again is a genuine re-completion, so it's allowed
            // to fire again rather than being suppressed after the first time.
            guard isComplete else { return }
            session.recipe.timesCooked += 1
            session.recipe.lastCookedDate = Date()
            try? modelContext.save()
        }
        .alert(
            session.isComplete ? "You Both Finished!" : "Partner Ended the Session",
            isPresented: .constant(session.partnerDidLeave)
        ) {
            Button("OK") {
                sessionStore.clear()
                path = NavigationPath()
            }
        } message: {
            Text(
                session.isComplete
                    ? "Nice work — head back to the recipe list whenever you're ready."
                    : "You can keep cooking on your own — the recipe is still right here."
            )
        }
    }

    private var timerFinishedBannerStack: some View {
        VStack(spacing: 8) {
            ForEach(timerFinishedBanners) { banner in
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                    Text("Timer finished: \(banner.instruction)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4, y: 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    timerFinishedBanners.removeAll { $0.id == banner.id }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.default, value: timerFinishedBanners.map(\.id))
    }

    // MARK: - Active step

    private var activeStepView: some View {
        VStack(spacing: 0) {
            ProgressIndicatorView(progressText: session.progressText, fraction: session.progressFraction)
                .padding(.top)

            if session.role != nil {
                PartnerStatusView(session: session)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            TimerStackView(timers: otherTimers)
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            if let step = session.currentStep {
                VStack(spacing: 20) {
                    // Grouped into one VoiceOver element (rather than a separately-focusable
                    // image and text) with an explicit "next step" action — the tap-to-advance
                    // gesture below only fires on a real touch, which VoiceOver intercepts for
                    // its own navigation, so without this a VoiceOver user would have no way to
                    // move forward at all.
                    Group {
                        PlaceholderPhotoView(systemImage: step.imageSystemName, tint: stepTint(for: step))
                            .frame(width: 220, height: 160)

                        Text(step.instruction)
                            .font(.system(size: 30, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            // Legibility comes first: the illustration sits above, text is never
                            // squeezed or overlapped by it.
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(session.progressText). \(step.instruction)")
                    .accessibilityAddTraits(session.isLastStep ? [] : .isButton)
                    .accessibilityHint(session.isLastStep ? "" : "Double tap to go to the next step")
                    .accessibilityAction {
                        guard !session.isLastStep else { return }
                        session.advance()
                    }

                    StepTimerControl(step: step, session: session)
                }
            }

            Spacer()

            if session.isLastStep {
                HoldToFinishButton { session.advance() }
                    .padding(.bottom, 12)
            }

            // Always available, even on the last step — the hold-to-finish control above adds
            // to this, it doesn't replace it.
            backButtonRow
        }
        // Most of the screen advances to the next step on tap — the large target is
        // deliberate: this needs to work reliably with wet or messy hands while cooking.
        // A left/right swipe does the same thing as a convenience, but is never required.
        // On the final step, tap/swipe-forward is disabled in favor of the deliberate
        // hold-to-finish control above — going back still works normally.
        .contentShape(Rectangle())
        .onTapGesture {
            guard !session.isLastStep else { return }
            session.advance()
        }
        .gesture(stepSwipeGesture)
    }

    private var stepSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal < 0 {
                    guard !session.isLastStep else { return }
                    session.advance()
                } else {
                    session.goBack()
                }
            }
    }

    /// Every timer that isn't the current step's own — mine on other steps, plus the partner's,
    /// each labeled with the task it's timing (see `TimerStackView`).
    private var otherTimers: [TimerChipInfo] {
        let mine = session.activeTimers
            .filter { $0.step.id != session.currentStep?.id }
            .map { TimerChipInfo(step: $0.step, remainingSeconds: $0.remainingSeconds, isMine: true) }
        let partner = session.partnerActiveTimers
            .map { TimerChipInfo(step: $0.step, remainingSeconds: $0.remainingSeconds, isMine: false) }
        return mine + partner
    }

    private var backButtonRow: some View {
        HStack {
            Button {
                if session.currentIndex == 0 {
                    // Nothing left to step back to within the recipe — leave the step screen
                    // entirely, back to the recipe overview. Never disabled/grayed: there's
                    // always somewhere sensible for this button to take you.
                    path.removeLast()
                } else {
                    session.goBack()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
            .padding()
            // An icon-only button synthesizes a poor default VoiceOver label ("chevron left
            // circle fill") — this also doubles as the one VoiceOver-reachable way to go back a
            // step, since the swipe-back gesture isn't reliably available while VoiceOver is on.
            .accessibilityLabel(session.currentIndex == 0 ? "Back to recipe overview" : "Previous step")

            Spacer()
        }
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Recipe Complete")
                .font(.title.bold())

            VStack(spacing: 12) {
                Button("Back to Recipes") {
                    sessionStore.clear()
                    path = NavigationPath()
                }
                .buttonStyle(.borderedProminent)

                // In case the last tap/hold past the final step was an accident and you're
                // not actually done cooking yet.
                Button("Go Back") {
                    session.goBack()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        switch session.currentStep?.assignee {
        case .personA: return Color.blue.opacity(0.08)
        case .personB: return Color.orange.opacity(0.08)
        case .shared: return Color.purple.opacity(0.08)
        default: return Color(.systemBackground)
        }
    }

    private func stepTint(for step: RecipeStep) -> Color {
        switch step.assignee {
        case .personA: return .blue
        case .personB: return .orange
        case .shared: return .purple
        case .solo: return .accentColor
        }
    }
}
