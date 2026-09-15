import SwiftUI
import Foundation
import CookingAppCore
import MultipeerConnectivity

struct PeerConnectionView: View {
    @State private var viewModel: PeerConnectionViewModel
    @Binding var path: NavigationPath
    @Environment(ActiveSessionStore.self) private var sessionStore

    /// Only meaningful if the user proceeds to host — the joiner is assigned whatever the host
    /// didn't pick, so there's nothing for the joiner to choose here.
    @State private var chosenRole: StepAssignee = .personA

    init(recipe: Recipe, path: Binding<NavigationPath>) {
        let cookName = UserDefaults.standard.string(forKey: "cookName")
        _viewModel = State(initialValue: PeerConnectionViewModel(
            recipe: recipe,
            peerSync: PeerSyncService(displayName: (cookName?.isEmpty ?? true) ? "Cook" : cookName!)
        ))
        _path = path
    }

    var body: some View {
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
        }
        .onChange(of: viewModel.didHandshake) { _, didHandshake in
            guard didHandshake, let stepAssignee = viewModel.resolvedStepAssignee else { return }
            let session = CookingSessionViewModel(
                recipe: viewModel.recipe,
                role: stepAssignee,
                peerSync: viewModel.peerSync
            )
            sessionStore.setActive(session)
            // Replace this connect screen in the stack rather than pushing on top of it, so
            // stepping back from the step screen later lands on the recipe overview, not here.
            path.removeLast()
            path.append(Route.steps(session))
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
                }

                Button("Host a two-person session") { viewModel.host(as: chosenRole) }
                    .buttonStyle(.borderedProminent)
                Button("Join a nearby session") { viewModel.join() }
                    .buttonStyle(.bordered)
            }

        case .advertising:
            VStack(spacing: 12) {
                ProgressView()
                Text("Waiting for your partner to join…")
                    .foregroundStyle(.secondary)
            }

        case .browsing:
            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for a nearby session…")
                        .foregroundStyle(.secondary)
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
                }
            }

        case .connecting, .connected:
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting…")
                    .foregroundStyle(.secondary)
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
}
