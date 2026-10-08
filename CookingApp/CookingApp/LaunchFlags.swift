import Foundation

/// Test-only launch arguments. Every flag is `false` in Release builds, so a shipped app can't be
/// switched into a test mode (in-memory store, cleared session) by a launch argument.
enum LaunchFlags {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    /// UI tests: in-memory store, no notification prompt, clean session.
    static let uiTesting = arguments.contains("-UITesting")
    /// UI tests: keep the persisted solo session (to verify resume after a relaunch).
    static let keepSession = arguments.contains("-UITestKeepSession")
    /// UI tests: don't reset the one-time Local Network explainer.
    static let skipExplainer = arguments.contains("-UITestSkipExplainer")
    #else
    static let uiTesting = false
    static let keepSession = false
    static let skipExplainer = false
    #endif
}
