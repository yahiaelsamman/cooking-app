import SwiftUI
import UIKit
import CookingAppCore

struct StepView: View {
    let session: CookingSessionViewModel
    @Binding var path: NavigationPath

    @State private var showTimerFinishedAlert = false
    @State private var finishedTimerStepInstruction = ""

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
        .onAppear {
            session.onTimerFinished = { step in
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

            if let runningStep = session.runningTimerStep, runningStep.id != session.currentStep?.id {
                elsewhereTimerBanner(for: runningStep)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

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

            backButtonRow
        }
        // Most of the screen advances to the next step on tap — the large target is
        // deliberate: this needs to work reliably with wet or messy hands while cooking.
        // A left/right swipe does the same thing as a convenience, but is never required.
        .contentShape(Rectangle())
        .onTapGesture { session.advance() }
        .gesture(stepSwipeGesture)
    }

    private var stepSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal < 0 {
                    session.advance()
                } else {
                    session.goBack()
                }
            }
    }

    private func elsewhereTimerBanner(for step: RecipeStep) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
            Text("Timer running on another step: \(StepTimerControl.formatted(session.timerRemainingSeconds))")
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {} // absorb — don't advance the current step when tapping this banner
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
                    path = NavigationPath()
                }
                .buttonStyle(.borderedProminent)

                // In case the last tap/swipe past the final step was an accident and you're
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
