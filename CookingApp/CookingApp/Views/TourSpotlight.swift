import SwiftUI

/// Collects the on-screen frame of every control a walkthrough might highlight, keyed by the same
/// id passed to `.tourAnchor`. Read back by `TourSpotlight` via `overlayPreferenceValue` to know
/// where to draw the highlight ring.
struct TourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Records this view's on-screen frame under `id` so a walkthrough can point at it — purely
    /// position tracking, no interaction. Pair with a call to `AppTour.notify(id)` from this
    /// control's own action (or an `.onChange` on the state it edits) to actually advance the
    /// tour when it's genuinely used.
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: TourAnchorPreferenceKey.self, value: .bounds) { [id: $0] }
    }
}

/// Draws the current step of a screen's `AppTour`: a pulsing ring around the real control (from
/// the frame `.tourAnchor` recorded) plus a callout explaining it, or — for a step with no single
/// control to point at — a centered callout with its own "Next" button.
///
/// Deliberately never intercepts touches over the highlighted control or anywhere else on the
/// real screen: the entire point of "click the real button to make it work" is that the button
/// underneath keeps working exactly as it always did. Only the callout's own buttons (and the
/// "Skip walkthrough" chip) opt back into hit-testing. This is why the tour advances from each
/// control's own action calling `AppTour.notify`, never from a gesture layered on top of this
/// view — a second gesture recognizer competing with, say, `StepView`'s tap/swipe/long-press mix
/// would risk breaking gestures that are already accessibility-audited.
struct TourSpotlight: View {
    @Bindable var tour: AppTour
    let anchors: [String: Anchor<CGRect>]
    /// Moved to the callout the moment a step begins or advances — see the `.onChange` below.
    /// Without this, a VoiceOver user gets a silently-inserted callout they'd only find by
    /// chance; a sighted user gets the same information for free from the pulsing ring + text.
    /// Focusing the callout also has VoiceOver announce it immediately, which doubles as the
    /// "announce this step" half of the fix — a separate `UIAccessibility.post(.announcement)`
    /// would be redundant on top of that.
    @AccessibilityFocusState private var isCalloutFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let step = tour.currentStep {
                    content(for: step, proxy: proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(tour.isActive)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: tour.currentStep?.id)
        .onChange(of: tour.currentStep?.id) { _, newID in
            guard newID != nil else { return }
            // A short delay lets this step's layout/animation settle first — moving VoiceOver
            // focus mid-transition is what usually causes focus to land on stale geometry.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isCalloutFocused = true
            }
        }
    }

    @ViewBuilder
    private func content(for step: TourStep, proxy: GeometryProxy) -> some View {
        let rect = step.targetID.flatMap { anchors[$0] }.map { proxy[$0] }

        ZStack {
            // A faint screen-wide tint draws the eye toward whatever's highlighted without
            // ever blocking a tap — see the doc comment above for why this matters here.
            Color.black.opacity(0.001)
                .allowsHitTesting(false)

            if let rect {
                highlightRing(around: rect)
            }

            calloutBubble(step: step, near: rect, in: proxy.size)

            skipChip
        }
    }

    private func highlightRing(around rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 4)
            .shadow(color: Color.accentColor.opacity(0.7), radius: 6)
            .frame(width: rect.width + 16, height: rect.height + 16)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func calloutBubble(step: TourStep, near rect: CGRect?, in screenSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

            if step.targetID == nil {
                Button("Next") { tour.advanceManually() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("tourNextButton")
            } else {
                Label("Tap it to continue", systemImage: "hand.tap.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(16)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .position(calloutPosition(near: rect, calloutHeight: 140, in: screenSize))
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title): \(step.message)")
        .accessibilityHint(step.targetID == nil ? "Double tap Next to continue" : "Use the highlighted control to continue")
        .accessibilityFocused($isCalloutFocused)
    }

    /// Below the target when there's room, else above it; centered on screen for an
    /// informational step with nothing to point at. Clamped so it never runs off either edge.
    private func calloutPosition(near rect: CGRect?, calloutHeight: CGFloat, in screenSize: CGSize) -> CGPoint {
        guard let rect else {
            return CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        }
        let margin: CGFloat = 24
        let x = min(max(screenSize.width / 2, 160), screenSize.width - 160)
        let spaceBelow = screenSize.height - rect.maxY
        if spaceBelow > calloutHeight + margin {
            return CGPoint(x: x, y: rect.maxY + margin + calloutHeight / 2)
        } else {
            return CGPoint(x: x, y: max(rect.minY - margin - calloutHeight / 2, calloutHeight / 2 + margin))
        }
    }

    /// The overlay ignores the safe area (so the dimming covers the whole screen), which makes
    /// the chip's own geometry report a zero inset and sit on the status bar — read it from the window.
    private static var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    private var skipChip: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip Walkthrough") { tour.skip() }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .accessibilityIdentifier("tourSkipButton")
            }
            .padding(.top, Self.topSafeInset + 8)
            .padding(.trailing, 16)
            Spacer()
        }
    }
}
