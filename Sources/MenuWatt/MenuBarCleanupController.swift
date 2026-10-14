import AppKit
import Combine
import MenuWattCore

@MainActor
final class MenuBarCleanupController: ObservableObject {
    @Published var configuration: MenuBarCleanupConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            save()
            if !configuration.enabled {
                isPaused = false
                revealMode = .collapsed
            }
            updateHotKeys()
            updateHoverMonitor()
            apply()
            scheduleRehide()
        }
    }
    @Published private(set) var entries: [MenuBarCleanupEntry] = []
    @Published private(set) var revealMode: MenuBarRevealMode = .collapsed
    @Published private(set) var isPaused = false
    @Published private(set) var status = "Menu bar cleanup is off."
    @Published private(set) var errorMessage: String?
    @Published private(set) var hotKeysAvailable = false
    @Published private(set) var hoverRevealed = false

    let isSupported: Bool
    private let defaults: UserDefaults
    private let ownBundleID: String
    private let runtime: MenuBarCleanupRuntime
    private var runningBundleIDs: Set<String> = []
    private var isSleeping = false
    private var runSequence: UInt64 = 0
    private var observers: [AnyCancellable] = []
    private var rehideTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private let sessionManager: MenuBarCleanupSessionManager
    private let hotKeyManager: MenuBarCleanupHotKeyManager
    private let hoverMonitor: MenuBarHoverMonitor
    private var hoverHideTask: Task<Void, Never>?
    private var isStarted = false
    private static let preferencePrefix = "menuBarCleanup."

    init(defaults: UserDefaults = .standard, runtime: MenuBarCleanupRuntime = .live,
         hoverMonitor: MenuBarHoverMonitor? = nil) {
        self.defaults = defaults
        self.runtime = runtime
        self.hoverMonitor = hoverMonitor ?? MenuBarHoverMonitor(snapshotProvider: runtime.hoverSnapshot)
        ownBundleID = Bundle.main.bundleIdentifier ?? "com.junsu.menuwatt"
        sessionManager = MenuBarCleanupSessionManager(
            makeSession: runtime.makeSession, activationTimeout: runtime.activationTimeout)
        hotKeyManager = MenuBarCleanupHotKeyManager(makeHotKeys: runtime.makeHotKeys)
        isSupported = runtime.isSupported
        let rawSections = defaults.dictionary(forKey: Self.preferencePrefix + "sections") as? [String: String] ?? [:]
        configuration = MenuBarCleanupConfiguration(
            enabled: defaults.bool(forKey: Self.preferencePrefix + "enabled"),
            keepActivityControlsHidden: defaults.object(forKey: Self.preferencePrefix + "hideActivityControls") as? Bool ?? true,
            autoRehide: defaults.object(forKey: Self.preferencePrefix + "autoRehide") as? Bool ?? true,
            revealOnHover: defaults.object(forKey: Self.preferencePrefix + "revealOnHover") as? Bool ?? false,
            sections: rawSections.compactMapValues(MenuBarItemSection.init(rawValue:))
        )
        if !isSupported { status = "Menu bar cleanup requires a supported macOS 27 build." }
    }

    var enabled: Bool {
        get { configuration.enabled }
        set { configuration.enabled = newValue }
    }

    var keepActivityControlsHidden: Bool {
        get { configuration.keepActivityControlsHidden }
        set { configuration.keepActivityControlsHidden = newValue }
    }

    var autoRehide: Bool {
        get { configuration.autoRehide }
        set { configuration.autoRehide = newValue }
    }

    var revealOnHover: Bool {
        get { configuration.revealOnHover }
        set { configuration.revealOnHover = newValue }
    }

    var isExpanded: Bool { revealMode != .collapsed }

    var canRevealItems: Bool { isStarted && isSupported && enabled && !isSleeping && !isPaused }

    func section(for id: String) -> MenuBarItemSection {
        configuration.sections[id] ?? .visible
    }

    func setSection(_ section: MenuBarItemSection, for id: String) {
        guard id != MenuBarCleanupPolicy.appKey(ownBundleID) else { return }
        if section == .visible {
            configuration.sections.removeValue(forKey: id)
        } else {
            configuration.sections[id] = section
        }
    }

    /// An explicit safe startup pauses before refresh can create an OS session.
    /// This is transient; the user's opt-in and icon choices remain untouched.
    func start(paused: Bool = false) {
        guard !isStarted else { return }
        isPaused = paused && enabled && isSupported
        isStarted = true
        runSequence &+= 1
        let run = runSequence
        let workspace = runtime.workspaceNotifications
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.runSequence == run else { return }
                    self.queueRefresh()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.runSequence == run else { return }
                    self.resumeAfterWake()
                }
            })
        }
        observers.append(workspace.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.runSequence == run else { return }
                self.prepareForSleep()
            }
        })
        observers.append(runtime.applicationNotifications.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.runSequence == run else { return }
                    self.queueRefresh(force: true)
                }
            })
        refresh()
        updateHotKeys()
        updateHoverMonitor()
    }

    func stop() {
        isStarted = false
        runSequence &+= 1
        observers.removeAll()
        refreshTask?.cancel()
        rehideTask?.cancel()
        hoverHideTask?.cancel()
        hoverMonitor.stop()
        hoverRevealed = false
        isSleeping = false
        isPaused = false
        revealMode = .collapsed
        retireHotKeys()
        restoreSession()
        errorMessage = nil
        status = "Menu bar cleanup is stopped."
    }

    /// A transient pause releases the OS restriction without writing preferences.
    /// It stays paused through refresh and wake until the user explicitly resumes.
    func pauseCleanup() {
        guard canRevealItems else { return }
        isPaused = true
        refreshTask?.cancel()
        rehideTask?.cancel()
        hoverHideTask?.cancel()
        hoverMonitor.stop()
        hoverRevealed = false
        revealMode = .collapsed
        restoreSession()
        retireHotKeys()
        updateHotKeys()
        errorMessage = nil
        status = pausedStatus
        MenuBarCleanupDiagnostics.paused()
    }

    func resumeCleanup() {
        guard isStarted, isSupported, enabled, !isSleeping, isPaused else { return }
        isPaused = false
        hoverRevealed = false
        revealMode = .collapsed
        retireHotKeys()
        updateHotKeys()
        updateHoverMonitor()
        refreshTask?.cancel()
        MenuBarCleanupDiagnostics.resumed()
        refresh()
    }

    func restoreSystemMenuBar() {
        enabled = false
        isPaused = false
        hoverRevealed = false
        // Also releases a session if restore is invoked while already disabled.
        restoreSession()
        errorMessage = nil
        revealMode = .collapsed
        status = "Menu bar cleanup is off."
    }

    func toggleHiddenItems() {
        guard canRevealItems else { return }
        hoverHideTask?.cancel()
        hoverRevealed = false
        revealMode = isExpanded ? .collapsed : .hidden
        refresh()
        scheduleRehide()
    }

    func showAllItems() {
        guard canRevealItems else { return }
        hoverHideTask?.cancel()
        hoverRevealed = false
        revealMode = .all
        refresh()
        scheduleRehide()
    }

    func refresh() {
        let apps = runtime.runningApps()
        runningBundleIDs = Set(apps.map(\.bundleID))
        entries = MenuBarCleanupCatalog.buildEntries(
            apps: apps, sections: configuration.sections,
            runningBundleIDs: runningBundleIDs, ownBundleID: ownBundleID
        )
        apply()
    }

    private func prepareForSleep() {
        guard isStarted else { return }
        isSleeping = true
        retireHotKeys()
        hoverMonitor.stop()
        hoverHideTask?.cancel()
        hoverRevealed = false
        refreshTask?.cancel()
        rehideTask?.cancel()
        revealMode = .collapsed
        restoreSession()
        errorMessage = nil
        status = isPaused ? pausedStatus : (enabled ? "Menu bar cleanup is paused for sleep." : "Menu bar cleanup is off.")
    }

    private func resumeAfterWake() {
        guard isStarted else { return }
        isSleeping = false
        hoverRevealed = false
        revealMode = .collapsed
        updateHotKeys()
        updateHoverMonitor()
        rehideTask?.cancel()
        queueRefresh(force: true)
    }

    private func queueRefresh(force: Bool = false) {
        guard isStarted, !isSleeping else { return }
        // Retire now so a pre-wake completion/timeout cannot affect recovery.
        if force {
            restoreSession()
            if enabled, isSupported, !isPaused { status = "Updating menu bar…" }
        }
        refreshTask?.cancel()
        let delay = runtime.refreshDelay
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isStarted, !self.isSleeping else { return }
            self.refresh()
        }
    }

    private func save() {
        defaults.set(configuration.enabled, forKey: Self.preferencePrefix + "enabled")
        defaults.set(configuration.keepActivityControlsHidden, forKey: Self.preferencePrefix + "hideActivityControls")
        defaults.set(configuration.autoRehide, forKey: Self.preferencePrefix + "autoRehide")
        defaults.set(configuration.revealOnHover, forKey: Self.preferencePrefix + "revealOnHover")
        defaults.set(configuration.sections.mapValues(\.rawValue), forKey: Self.preferencePrefix + "sections")
    }

    private func restoreSession() {
        sessionManager.retire()
    }

    private var pausedStatus: String {
        "Cleanup is paused. Resume Cleanup when you’re finished using system controls."
    }

    private var activeStatus: String {
        switch revealMode {
        case .collapsed: "Menu bar cleanup is active."
        case .hidden: "Hidden icons are revealed."
        case .all: "All app icons are revealed."
        }
    }

    private func apply() {
        guard isStarted, !isSleeping else { return }
        guard isSupported else { return }
        guard !isPaused else {
            errorMessage = nil
            status = pausedStatus
            return
        }
        let plan = MenuBarCleanupPolicy.plan(configuration: configuration,
            runningBundleIDs: runningBundleIDs, ownBundleID: ownBundleID, reveal: revealMode)
        guard plan.needsSession else {
            restoreSession()
            errorMessage = nil
            status = enabled ? "All menu bar controls are visible." : "Menu bar cleanup is off."
            return
        }
        guard sessionManager.currentPlan != plan else {
            if !sessionManager.activating { status = activeStatus }
            return
        }

        errorMessage = nil
        status = "Updating menu bar…"
        let run = runSequence
        sessionManager.apply(plan, isLive: { [weak self] in
            guard let self else { return false }
            return self.isStarted && self.runSequence == run
        }) { [weak self] failure in
            guard let self, self.isStarted, self.runSequence == run else { return }
            if let failure {
                self.errorMessage = failure.userMessage
                self.status = "The original menu bar has been restored."
            } else {
                self.errorMessage = nil
                self.status = self.activeStatus
            }
        }
    }

    private func retireHotKeys() {
        hotKeyManager.retire()
        hotKeysAvailable = false
    }

    private func updateHotKeys() {
        guard isStarted, isSupported, enabled, !isSleeping else {
            retireHotKeys()
            return
        }
        hotKeyManager.ensureRegistered { [weak self] action in
            guard let self, self.isStarted, self.enabled, !self.isSleeping else { return }
            if action == 1 { self.toggleHiddenItems() }
            if action == 2 { self.restoreSystemMenuBar() }
        }
        hotKeysAvailable = hotKeyManager.isAvailable
    }

    private func scheduleRehide() {
        rehideTask?.cancel()
        // Hover owns its exit grace period. Configuration edits must not add a
        // competing 15-second timer while the pointer is still over the bar.
        guard canRevealItems, autoRehide, isExpanded, !hoverRevealed else { return }
        let delay = runtime.rehideDelay
        rehideTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.canRevealItems,
                      self.isExpanded, !self.hoverRevealed else { return }
                if self.hoverMonitor.preventsAutomaticCollapse { continue }
                self.revealMode = .collapsed
                self.apply()
                return
            }
        }
    }

    // MARK: - Hover reveal

    private func updateHoverMonitor() {
        guard isStarted, isSupported, enabled, revealOnHover, !isSleeping, !isPaused else {
            hoverHideTask?.cancel()
            hoverMonitor.stop()
            // Leaving hover mode collapses what hover opened, like pause does.
            if hoverRevealed {
                hoverRevealed = false
                revealMode = .collapsed
                apply()
            }
            return
        }
        let run = runSequence
        hoverMonitor.start(onEnter: { [weak self] in
            guard let self, self.runSequence == run else { return }
            self.hoverDidEnter()
        }, onExit: { [weak self] in
            guard let self, self.runSequence == run else { return }
            self.hoverDidExit()
        })
    }

    private func hoverDidEnter() {
        hoverHideTask?.cancel()
        guard canRevealItems, configuration.revealOnHover else { return }
        guard !isExpanded else { return }
        rehideTask?.cancel()
        hoverRevealed = true
        revealMode = .hidden
        refresh()
    }

    private func hoverDidExit() {
        hoverHideTask?.cancel()
        // Only collapse what hover opened; a manual reveal stays until its
        // own timer or toggle. A short grace period absorbs edge flicker.
        guard hoverRevealed, isExpanded else { return }
        hoverHideTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self,
                      self.hoverRevealed, self.canRevealItems else { return }
                // Do not invalidate the visibility assertion underneath a menu,
                // attached popup or drag that began during this grace period.
                if self.hoverMonitor.preventsAutomaticCollapse { continue }
                self.hoverRevealed = false
                self.revealMode = .collapsed
                self.apply()
                return
            }
        }
    }
}
