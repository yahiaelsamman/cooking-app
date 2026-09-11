import SwiftUI
import UIKit
import CookingAppCore

struct StepView: View {
    let session: CookingSessionViewModel
    @Binding var path: NavigationPath
    @Environment(ActiveSessionStore.self) private var sessionStore

    @State private var showTimerFinishedAlert = false
    @State private var finishedTimerStepInstruction = ""
    @State private var showEndSessionConfirm = false

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if session.isComplete {
                completionView
            } else {
                activeStepView
            }
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
            NotificationScheduler.requestAuthorizationIfNeeded()
            session.onTimerScheduled = { step, duration in
                NotificationScheduler.schedule(step: step, durationSeconds: duration)
            }
            session.onTimerUnscheduled = { step in
                NotificationScheduler.cancel(step: step)
            }
            session.onTimerFinished = { step in
                // Cancel the corresponding notification — we're about to show our own in-app
                // alert, and reaching this callback at all means the app was foregrounded when
                // the timer hit zero, so the notification would just be a redundant duplicate.
                NotificationScheduler.cancel(step: step)
                finishedTimerStepInstruction = step.instruction
                showTimerFinishedAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .alert("Timer Finished", isPresented: $showTimerFinishedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(finishedTimerStepInstruction)
        }
        .alert("Partner Ended the Session", isPresented: .constant(session.partnerDidLeave)) {
            Button("OK") {
                sessionStore.clear()
                path = NavigationPath()
            }
        } message: {
            Text("You can keep cooking on your own — the recipe is still right here.")
        }
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
                    Image(systemName: step.imageSystemName)
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
                        .frame(height: 90)

                    Text(step.instruction)
                        .font(.system(size: 30, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        // Legibility comes first: the illustration sits above, text is never
                        // squeezed or overlapped by it.
                        .fixedSize(horizontal: false, vertical: true)

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
                session.goBack()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .disabled(session.currentIndex == 0)
            .opacity(session.currentIndex == 0 ? 0.3 : 1)

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
}
