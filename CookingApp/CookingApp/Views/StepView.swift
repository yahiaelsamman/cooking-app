import SwiftUI
import SwiftData
import UIKit
import AudioToolbox
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
    @Binding var path: [Route]
    @Environment(ActiveSessionStore.self) private var sessionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationPresentationState) private var notificationPresentationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var timerFinishedBanners: [TimerFinishedBanner] = []
    @State private var showEndSessionConfirm = false
    @State private var showIngredientChecklist = false
    @State private var checkedIngredientIDs: Set<Ingredient.ID> = []
    @AppStorage("cookExpertise") private var cookExpertiseRaw: String = CookExpertise.intermediate.rawValue
    @AppStorage("hasSeenStepTour") private var hasSeenStepTour = false
    @AppStorage("hasSeenTimerTourTip") private var hasSeenTimerTourTip = false
    @AppStorage("hasSeenFinishTourTip") private var hasSeenFinishTourTip = false
    @State private var tour = AppTour()
    /// Which "have I seen this" flag to flip once `tour` finishes — the step screen runs three
    /// independent one-time walkthroughs (the front-loaded gesture tour, plus two dynamic tips
    /// that only make sense once you actually reach a timed step / the last step), all through
    /// this one `AppTour` instance, so something has to remember which is currently running.
    @State private var activeTourKind: StepTourKind?

    private var cookExpertise: CookExpertise {
        CookExpertise(rawValue: cookExpertiseRaw) ?? .intermediate
    }

    private enum StepTourKind {
        case gestures, timer, finish
    }

    private var gestureTourSteps: [TourStep] {
        [
            TourStep(
                target: "stepAdvance",
                title: "Move Through the Recipe",
                message: "Tap the right side of the screen to move on, or the left side to go back. Swiping works too."
            ),
            TourStep(
                target: "ingredientChecklistButton",
                title: "Ingredient checklist",
                message: "Tap here anytime to check off ingredients as you use them."
            ),
            TourStep(
                id: "stepBack",
                title: "Going Back",
                message: "Use the arrow in the bottom-left corner anytime you need to go back a step."
            )
        ]
    }

    /// Called on appear and every time the current step (or the tour) changes — picks whichever
    /// one-time tip is now due, but never interrupts one that's already showing.
    private func beginNextTourIfNeeded() {
        guard !tour.isActive else { return }
        // Each flag is marked seen the moment its tour begins, not when every highlighted
        // control has actually been used — tapping through steps without pausing to use the
        // timer button (the natural thing to do) would otherwise leave that tip stuck active
        // forever, replaying every time a timed step comes up.
        if !hasSeenStepTour {
            activeTourKind = .gestures
            hasSeenStepTour = true
            tour.begin(gestureTourSteps)
        } else if let step = session.currentStep, step.timerSeconds != nil, !hasSeenTimerTourTip {
            activeTourKind = .timer
            hasSeenTimerTourTip = true
            tour.begin([
                TourStep(
                    target: "stepTimerButton",
                    title: "Timers",
                    message: "Tap here to start a timer for this step — it keeps counting down even if you move to another step."
                )
            ])
        } else if session.isLastStep, !hasSeenFinishTourTip {
            activeTourKind = .finish
            hasSeenFinishTourTip = true
            tour.begin([
                TourStep(
                    target: "holdToFinishButton",
                    title: "Finishing Up",
                    message: "Press and hold the checkmark for a second to finish cooking."
                )
            ])
        }
    }

    /// True once both people have actually finished the recipe — my own last step, and the
    /// partner's, both reached. Detected purely from progress already exchanged (`advance()`
    /// already sends a `progressUpdate` at the completing step), no extra message needed.
    private var bothFinished: Bool {
        session.role != nil && session.isComplete && session.partnerProgressFraction == 1.0
    }

    @State private var stepAreaWidth: CGFloat = 0
    @State private var notificationsDenied = false
    /// Moves VoiceOver straight to the step text on arrival; otherwise focus starts on the toolbar.
    @AccessibilityFocusState private var stepFocused: Bool
    @State private var notificationHintDismissed = false

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor.ignoresSafeArea()

            if session.isComplete {
                completionView
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            } else {
                activeStepView
            }

            timerFinishedBannerStack
        }
        // `ConfettiView` (shown alongside `completionView`) already gates its own motion behind
        // this same environment value — this is the matching gate for the screen-swap transition
        // itself: an instant swap with no scale/spring under Reduce Motion, same as
        // `.opacity`-only would produce, rather than skipping the `.animation` call and letting
        // its default implicit animation apply anyway.
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: session.isComplete)
        .navigationBarBackButtonHidden(true)
        .disablesInteractiveSwipeBack()
        .toolbar {
            if !session.isComplete {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showIngredientChecklist = true
                        tour.notify("ingredientChecklistButton")
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Ingredient checklist")
                    .accessibilityIdentifier("ingredientChecklistButton")
                    .tourAnchor("ingredientChecklistButton")
                }
            }
            if session.role != nil && !session.isComplete && session.partnerConnectionState != .idle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End Session", role: .destructive) {
                        showEndSessionConfirm = true
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
            if !session.isComplete {
                TourSpotlight(tour: tour, anchors: anchors)
            }
        }
        .onChange(of: tour.isActive) { wasActive, isActive in
            guard wasActive && !isActive else { return }
            activeTourKind = nil
            beginNextTourIfNeeded()
        }
        .onChange(of: session.currentStep?.id) { _, _ in
            beginNextTourIfNeeded()
        }
        .sheet(isPresented: $showIngredientChecklist) {
            IngredientChecklistView(ingredients: session.recipe.ingredients, checkedIDs: $checkedIngredientIDs)
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
        .task(id: session.activeTimers.count) {
            notificationsDenied = await NotificationScheduler.isDenied()
        }
        .onAppear {
            notificationPresentationState.isStepViewVisible = true
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
                // The system banner and its sound are suppressed while this screen is visible
                // (see `NotificationDelegate`), so without an audible cue the only signals are a
                // haptic and a toast — neither reaches a phone propped across the kitchen, or
                // someone using VoiceOver. Respects the ringer switch like any system sound.
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                var announcement = AttributedString("Timer finished: \(step.instruction)")
                announcement.accessibilitySpeechAnnouncementPriority = .high
                AccessibilityNotification.Announcement(announcement).post()
                // Under VoiceOver a 4s toast is easy to miss or lose focus on, so it stays until
                // dismissed there.
                if !UIAccessibility.isVoiceOverRunning {
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        timerFinishedBanners.removeAll { $0.id == banner.id }
                    }
                }
            }
            if session.role != nil {
                session.announcePresence(isAway: false)
            }
            // Cooking is a hands-off, glance-at-the-screen activity — messy hands mean a locked
            // screen mid-step is a real interruption, not a minor one. Every mainstream recipe
            // app disables the idle timer for exactly this reason while a step is on screen.
            UIApplication.shared.isIdleTimerDisabled = true
            if !session.isComplete {
                beginNextTourIfNeeded()
            }
            if UIAccessibility.isVoiceOverRunning, !session.isComplete {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    // The tour callout takes focus itself when it is showing.
                    if !tour.isActive { stepFocused = true }
                }
            }
        }
        .onDisappear {
            if session.role != nil {
                session.announcePresence(isAway: true)
            }
            // Restore normal auto-lock the moment cooking isn't the active screen — never leave
            // the device unable to sleep just because it once showed a recipe step.
            UIApplication.shared.isIdleTimerDisabled = false
            // Flip the shared flag first so a timer that finishes right after this view tears
            // down lets the system banner through (see `NotificationDelegate`), then clear
            // `onTimerFinished` itself — it's the one closure here that touches this view's own
            // `@State`, which becomes stale (no longer attached to anything on screen) the moment
            // `StepView` disappears. `onTimerScheduled`/`onTimerUnscheduled` stay assigned: they
            // only forward to the stateless `NotificationScheduler`, so they're still correct to
            // run while this view isn't visible.
            notificationPresentationState.isStepViewVisible = false
            session.onTimerFinished = nil
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
        // A focused VoiceOver element doesn't re-speak when its label changes, so advancing,
        // going back and finishing were silent. Announce from one place so every path (tap zone,
        // swipe, accessibility action, back button, partner-driven) is covered.
        .onChange(of: session.currentIndex) { _, _ in
            guard UIAccessibility.isVoiceOverRunning, !session.isComplete,
                  let step = session.currentStep else { return }
            let suffix = session.isLastStep ? " Last step. Use Finish Recipe." : ""
            let index = session.currentIndex
            var text = "\(session.progressText). \(step.instruction).\(suffix)"
            if cookExpertise.prefersVerboseGuidance, let hint = step.checkHint {
                text += " To check: \(hint)"
            }
            // Short delay so the element's own re-read/activation feedback doesn't cancel it, and
            // high priority so it isn't dropped. Skipped if the step changed again meanwhile.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard session.currentIndex == index, !session.isComplete, !tour.isActive else { return }
                var announcement = AttributedString(text)
                announcement.accessibilitySpeechAnnouncementPriority = .high
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
        .onChange(of: session.isComplete) { _, isComplete in
            guard UIAccessibility.isVoiceOverRunning else { return }
            if isComplete {
                AccessibilityNotification.ScreenChanged("Recipe complete").post()
            } else {
                // Going back from the completion screen: put focus back on the step.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if !session.isComplete, !tour.isActive { stepFocused = true }
                }
            }
        }
        .alert(
            session.isComplete ? "You Both Finished!" : "Partner Ended the Session",
            isPresented: .constant(session.partnerDidLeave)
        ) {
            Button("OK") {
                sessionStore.clear()
                path = []
            }
        } message: {
            Text(
                session.isComplete
                    ? "Nice work — head back to the recipe list whenever you're ready."
                    : "Your partner ended the session. Tap OK to go back to your recipes."
            )
        }
    }

    private var timerFinishedBannerStack: some View {
        VStack(spacing: 8) {
            ForEach(timerFinishedBanners) { banner in
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .accessibilityHidden(true)
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
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to dismiss")
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(reduceMotion ? nil : .default, value: timerFinishedBanners.map(\.id))
    }

    // MARK: - Active step

    private var activeStepView: some View {
        VStack(spacing: 0) {
            ProgressIndicatorView(progressText: session.progressText, fraction: session.progressFraction)
                .padding(.top)

            // The background/tint below is color-only otherwise (blue/orange/purple by
            // assignee) — a real gap for colorblind users in two-person mode, unlike
            // `RecipeDetailView`'s overview, which already labels the same grouping in text
            // ("Person A"/"Together"). Only shown in two-person mode: a solo session's steps are
            // all `.solo`, which `backgroundColor`/`stepTint` don't color-code at all.
            if let assigneeLabel = currentStepAssigneeLabel {
                Text(assigneeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            if session.role != nil {
                PartnerStatusView(session: session)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            TimerStackView(timers: otherTimers)
                .padding(.horizontal)
                .padding(.top, 8)

            if notificationsDenied && !notificationHintDismissed && !session.activeTimers.isEmpty {
                notificationsOffHint
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Spacer()

            if let step = session.currentStep {
                VStack(spacing: 20) {
                    // Grouped into one VoiceOver element (rather than a separately-focusable
                    // image and text) with an explicit "next step" action — the tap-to-advance
                    // gesture below only fires on a real touch, which VoiceOver intercepts for
                    // its own navigation, so without this a VoiceOver user would have no way to
                    // move forward at all.
                    // A real container, not `Group` — `Group` has no frame of its own, so
                    // `.tourAnchor` below would only ever capture whichever child SwiftUI
                    // happens to report last, not the photo+text pair together.
                    VStack(spacing: 20) {
                        // Flexible, not a fixed size: the instruction text below is
                        // `.fixedSize(vertical: true)` (always gets exactly the height it needs,
                        // never compressed), so whatever's left over in this VStack goes to the
                        // image — it grows as large as the current step's content allows, capped
                        // just so it can't dominate a very short instruction on a tall screen.
                        StepIllustrationView(step: step, tint: stepTint(for: step))
                            .frame(maxWidth: .infinity, maxHeight: 380)
                            .clipped()
                            .padding(.horizontal, 20)

                        Text(step.instruction)
                            .font(.system(.title, weight: .semibold))
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
                        tour.notify("stepAdvance")
                    }
                    .accessibilityFocused($stepFocused)
                    .tourAnchor("stepAdvance")

                    DonenessHintView(checkHint: step.checkHint, expertise: cookExpertise)
                        .id(step.id)

                    StepTimerControl(step: step, session: session) {
                        tour.notify("stepTimerButton")
                    }
                }
            }

            Spacer()

            if session.isLastStep {
                HoldToFinishButton {
                    session.advance()
                    tour.notify("holdToFinishButton")
                }
                .tourAnchor("holdToFinishButton")
                .padding(.bottom, 12)
            }

            // Always available, even on the last step — the hold-to-finish control above adds
            // to this, it doesn't replace it.
            backButtonRow
        }
        // Tap zones, like most story/step-through apps: the left third steps back, the rest
        // advances. The large targets are deliberate — this needs to work reliably with wet or
        // messy hands while cooking. A left/right swipe does the same as a convenience, but is
        // never required. On the final step, tap-forward is disabled in favor of the deliberate
        // hold-to-finish control above. On the first step the back zone does nothing (rather than
        // leaving the screen) so a stray edge tap can't throw you out of the recipe — the back
        // button below still does that.
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { stepAreaWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in stepAreaWidth = width }
            }
        )
        .onTapGesture { location in
            if stepAreaWidth > 0, location.x < stepAreaWidth / 3 {
                guard session.currentIndex > 0 else { return }
                session.goBack()
            } else {
                guard !session.isLastStep else { return }
                session.advance()
                tour.notify("stepAdvance")
            }
        }
        .gesture(stepSwipeGesture)
    }

    /// Shown only while a timer is running with notifications denied — the one situation where
    /// the denial actually costs the user something (a timer finishing while backgrounded).
    private var notificationsOffHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .accessibilityHidden(true)
            Text("Notifications are off, so you won't hear this timer if you leave the app.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            Button {
                notificationHintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                    tour.notify("stepAdvance")
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
                    .foregroundStyle(.primary.opacity(0.55))
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
        ZStack {
            ConfettiView()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Recipe Complete")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    Button("Back to Recipes") {
                        sessionStore.clear()
                        path = []
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
        // The enclosing ZStack aligns to .top, so without this the card hugs the top of the
        // screen instead of sitting where your eye actually lands after finishing a recipe.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Text counterpart to `backgroundColor`'s color-only assignee coding — `nil` for a solo
    /// session's `.solo` steps, which `backgroundColor` doesn't color-code either.
    private var currentStepAssigneeLabel: String? {
        switch session.currentStep?.assignee {
        case .personA: return session.role == .personA ? "Your steps (Person A)" : "Your partner's steps (Person A)"
        case .personB: return session.role == .personB ? "Your steps (Person B)" : "Your partner's steps (Person B)"
        case .shared: return "Together"
        case .solo, nil: return nil
        }
    }
}
