/// Opt-in for inspecting the app without applying its saved cleanup at launch.
/// Normal launch behavior stays unchanged; this does not persist a preference.
struct MenuBarCleanupStartupOptions {
    let startsPaused: Bool

    init(environment: [String: String]) {
        startsPaused = environment["MENUWATT_START_CLEANUP_PAUSED"] == "1"
    }

    @MainActor
    func startCleanup(_ controller: MenuBarCleanupController) {
        controller.start(paused: startsPaused)
    }
}
