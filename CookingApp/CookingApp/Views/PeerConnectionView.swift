import SwiftUI
import Foundation
import CookingAppCore
import MultipeerConnectivity

struct PeerConnectionView: View {
    // Created once on first appearance. Building it in `init` re-created a PeerSyncService
    // (MCPeerID + MCSession) every time the parent re-evaluated the destination closure.
    @State private var model: PeerConnectionViewModel?
    private let recipe: Recipe
    @State private var searchTimedOut = false
    @Environment(\.openURL) private var openURL
    @Binding var path: [Route]
    @Environment(ActiveSessionStore.self) private var sessionStore

    /// Only meaningful if the user proceeds to host — the joiner is assigned whatever the host
    /// didn't pick, so there's nothing for the joiner to choose here.
    @State private var chosenRole: StepAssignee = .personA
    private let servingsScaleFactor: Double

    // `@MainActor`: `PeerConnectionViewModel`/`PeerSyncService` are both `@MainActor` now (see
    // their doc comments in CookingAppCore) — a plain View `init` isn't implicitly MainActor
    // just because `body` is, so constructing them here needs this annotation explicitly.
    @MainActor
    init(recipe: Recipe, servingsScaleFactor: Double = 1, path: Binding<[Route]>) {
        self.servingsScaleFactor = servingsScaleFactor
        self.recipe = recipe
        _path = path
    }

    /// Only read from the `model != nil` branch of `body` (and callbacks it installs).
    private var viewModel: PeerConnectionViewModel { model! }

    private static var cookDisplayName: String {
        let cookName = UserDefaults.standard.string(forKey: "cookName")
        return (cookName?.isEmpty ?? true) ? "Cook" : cookName!
    }

    var body: some View {
        Group {
            if model != nil {
                connectBody
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                model = PeerConnectionViewModel(recipe: recipe, peerSync: PeerSyncService(displayName: Self.cookDisplayName))
            }
        }
    }

    private var connectBody: some View {
        VStack(spacing: 24) {
            Text(viewModel.recipe.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            content

            Spacer()
        }
        .padding()
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.connectionState) { _, newState in
            // The host has no recipeSync message to wait on — it sends that message, it
            // doesn't receive one — so its own connection reaching .connected is the signal.
            if newState == .connected {
                viewModel.hostDidConnect()
            }
            // Connection changes swap the screen's content silently; say them aloud for VoiceOver.
            switch newState {
            case .advertising: AccessibilityNotification.Announcement("Waiting for your partner").post()
            case .connecting: AccessibilityNotification.Announcement("Connecting").post()
            case .disconnected: AccessibilityNotification.Announcement("Connection lost. Try again to reconnect.").post()
            default: break
            }
        }
        .task(id: viewModel.connectionState) {
            // After ~10s of looking with nobody found, offer the Local Network hint.
            searchTimedOut = false
            let state = viewModel.connectionState
            guard state == .advertising || state == .browsing else { return }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { searchTimedOut = true }
        }
        .onChange(of: viewModel.recipeMismatch) { _, mismatch in
            if mismatch {
                AccessibilityNotification.Announcement("You and your partner picked different recipes.").post()
            }
        }
        .onChange(of: viewModel.didHandshake) { _, didHandshake in
            guard didHandshake, let stepAssignee = viewModel.resolvedStepAssignee else { return }
            let session = CookingSessionViewModel(
                recipe: viewModel.recipe,
                role: stepAssignee,
                peerSync: viewModel.peerSync
            )
            session.servingsScaleFactor = servingsScaleFactor
            sessionStore.setActive(session)
            // Replace this connect screen in the stack rather than pushing on top of it, so
            // stepping back from the step screen later lands on the recipe overview, not here.
            path.removeLast()
            path.append(.steps(session))
        }
        .onDisappear {
            if !viewModel.didHandshake {
                viewModel.cancel()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.connectionState {
        case .idle:
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If you host, you'll be:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Your role", selection: $chosenRole) {
                        Text("Person A").tag(StepAssignee.personA)
                        Text("Person B").tag(StepAssignee.personB)
                    }
                    .pickerStyle(.segmented)

                    if let rolePreview {
                        Text(rolePreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Host a two-person session") { viewModel.host(as: chosenRole) }
                    .buttonStyle(.borderedProminent)
                Button("Join a nearby session") { viewModel.join() }
                    .buttonStyle(.bordered)
            }

        case .advertising:
            VStack(spacing: 12) {
                if let failure = viewModel.peerSync.startFailure {
                    localNetworkProblem(failure)
                } else {
                    ProgressView()
                    Text("Waiting for your partner to join…")
                        .foregroundStyle(.secondary)
                    if searchTimedOut { localNetworkHint }
                }
                cancelButton
            }

        case .browsing:
            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 12) {
                    if let failure = viewModel.peerSync.startFailure {
                        localNetworkProblem(failure)
                    } else {
                        ProgressView()
                        Text("Looking for a nearby session…")
                            .foregroundStyle(.secondary)
                        if searchTimedOut { localNetworkHint }
                    }
                    cancelButton
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby sessions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.discoveredPeers, id: \.self) { peer in
                        Button(peer.displayName) {
                            viewModel.connect(to: peer)
                        }
                        .buttonStyle(.bordered)
                    }
                    cancelButton
                }
            }

        case .connecting, .connected:
            if viewModel.recipeMismatch {
                VStack(spacing: 12) {
                    Text("Different recipes")
                        .font(.headline)
                    Text("You and your partner picked different recipes. Go back, choose the same recipe, and join again.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { viewModel.cancel() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting…")
                        .foregroundStyle(.secondary)
                    cancelButton
                }
            }

        case .disconnected:
            VStack(spacing: 12) {
                Text("Connection lost")
                    .foregroundStyle(.red)
                Button("Try Again") { viewModel.cancel() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { viewModel.cancel() }
            .buttonStyle(.bordered)
    }

    private var localNetworkHint: some View {
        VStack(spacing: 8) {
            Text("Nobody found yet. Local Network access needed: Settings > Privacy > Local Network.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            openSettingsButton
        }
    }

    private func localNetworkProblem(_ detail: String) -> some View {
        VStack(spacing: 8) {
            Text("Local Network access needed")
                .font(.headline)
            Text("Settings > Privacy > Local Network")
                .font(.subheadline)
            Text(detail)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            openSettingsButton
        }
    }

    private var openSettingsButton: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(.borderedProminent)
    }

    /// A one-line, side-by-side preview of what each role actually does for *this* recipe —
    /// turns the role picker from a blind choice into an informed one. Shown regardless of which
    /// role is currently selected (it describes what both roles do, not just the chosen one), and
    /// built entirely from this recipe's own hand-authored `twoPersonSteps` — no placeholder text.
    private var rolePreview: String? {
        guard let steps = viewModel.recipe.twoPersonSteps,
              let personAStep = steps.first(where: { $0.assignee == .personA }),
              let personBStep = steps.first(where: { $0.assignee == .personB }) else {
            return nil
        }
        return "Person A: \(Self.summarize(personAStep.instruction)) · Person B: \(Self.summarize(personBStep.instruction))"
    }

    /// Trims a full step instruction down to a short, glanceable phrase — cutting at the nearest
    /// word boundary rather than mid-word, and stripping any trailing punctuation so it reads as
    /// a fragment ("Cook the pasta"), not a truncated sentence.
    private static func summarize(_ instruction: String, limit: Int = 32) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: limit)
        let truncated = trimmed[..<cutoff]
        let words = truncated.split(separator: " ").dropLast()
        let phrase = words.isEmpty ? String(truncated) : words.joined(separator: " ")
        return phrase.trimmingCharacters(in: .whitespaces) + "…"
    }
}
