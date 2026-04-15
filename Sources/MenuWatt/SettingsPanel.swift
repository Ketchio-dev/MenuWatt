import AppKit
import SwiftUI

private enum SettingsPanelStyle {
    static let windowSize = NSSize(width: 720, height: 520)
    static let windowTitle = "MenuWatt Settings"
}

/// A standalone settings window for the app.
/// Since menu bar accessory apps cannot use SwiftUI's Settings scene reliably,
/// we host the settings view in a regular NSWindow.
@MainActor
final class SettingsPanel {

    private var window: NSWindow?
    private let preferences: AppPreferences
    private let updateChecker: UpdateChecker

    init(preferences: AppPreferences, updateChecker: UpdateChecker) {
        self.preferences = preferences
        self.updateChecker = updateChecker
    }

    func show() {
        preferences.dismissLaunchAtLoginError()

        if let window, window.isVisible {
            present(window)
            return
        }

        let newWindow = makeWindow()
        self.window = newWindow
        present(newWindow)
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let settingsView = SettingsContentView(preferences: preferences, updateChecker: updateChecker)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsPanelStyle.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsPanelStyle.windowTitle
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.contentView = hostingView
        window.minSize = SettingsPanelStyle.windowSize
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}

// MARK: - Settings Content

private struct SettingsContentView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var updateChecker: UpdateChecker
    @State private var selectedPane: SettingsPane = .overview

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedPane)
                .frame(width: 200)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            ManualOnlyScrollView {
                selectedPaneView
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsPanelStyle.windowSize.width,
            idealWidth: SettingsPanelStyle.windowSize.width,
            minHeight: SettingsPanelStyle.windowSize.height,
            idealHeight: SettingsPanelStyle.windowSize.height
        )
    }

    @ViewBuilder
    private var selectedPaneView: some View {
        switch selectedPane {
        case .overview:
            OverviewSettingsPane(preferences: preferences)
        case .notifications:
            NotificationsSettingsPane(preferences: preferences)
        case .updates:
            UpdatesSettingsPane(preferences: preferences, updateChecker: updateChecker)
        case .about:
            AboutSettingsPane()
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MenuWatt")
                        .font(.system(size: 14, weight: .semibold))
                    Text(versionString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(
                        pane: pane,
                        isSelected: selection == pane,
                        action: { selection = pane }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(version)"
    }

    private var appIconImage: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName), icon.size.width > 0 {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.symbolName)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ManualOnlyScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> ManualOnlyScrollContainer<Content> {
        ManualOnlyScrollContainer(rootView: content)
    }

    func updateNSView(_ nsView: ManualOnlyScrollContainer<Content>, context: Context) {
        nsView.update(rootView: content)
    }
}

private final class ManualOnlyScrollContainer<Content: View>: NSView {
    private let scrollView = ManualOnlyNSScrollView()
    private let hostingView: NSHostingView<Content>

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = hostingView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: bounds.width, height: fittingSize.height))
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

private final class ManualOnlyNSScrollView: NSScrollView {
    private var hasReceivedExplicitScroll = false

    override func scrollWheel(with event: NSEvent) {
        hasReceivedExplicitScroll = true
        super.scrollWheel(with: event)
    }

    override func autoscroll(with event: NSEvent) -> Bool {
        guard hasReceivedExplicitScroll else {
            return false
        }

        return super.autoscroll(with: event)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case notifications
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .notifications: return "Notifications"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "house"
        case .notifications: return "bell.badge"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

private struct OverviewSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferences.launchesAtLogin },
            set: { preferences.setLaunchAtLogin($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPaneTitle(
                title: "Overview",
                subtitle: "Customize how MenuWatt starts and what it shows in your menu bar."
            )

            SettingsCard(title: "Startup", systemImage: "power") {
                SettingsRow(label: "Launch at Login") {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                }

                if let launchAtLoginError = preferences.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            preferences.dismissLaunchAtLoginError()
                        }
                }
            }

            SettingsCard(title: "Menu Bar Display", systemImage: "menubar.rectangle") {
                SettingsRow(label: "Indicator") {
                    Picker("", selection: $preferences.menuBarIndicator) {
                        ForEach(MenuBarIndicator.allCases) { indicator in
                            Text(indicator.title).tag(indicator)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                SettingsRow(label: "Update interval") {
                    Picker("", selection: $preferences.refreshInterval) {
                        ForEach(MenuBarRefreshInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                SettingsRow(label: "Show pixel character") {
                    Toggle("", isOn: $preferences.showsSprite)
                        .labelsHidden()
                }

                Text("Indicator and pixel character appear in your macOS menu bar. Longer update intervals save battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            SettingsCard(title: "Dashboard Sections", systemImage: "square.stack.3d.up") {
                ForEach(DashboardSection.allCases) { section in
                    SettingsRow(label: section.title) {
                        Toggle("", isOn: dashboardSectionBinding(for: section))
                            .labelsHidden()
                    }
                }

                Text("Choose which sections appear in the menu bar panel. Hidden sections are skipped but still sampled in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func dashboardSectionBinding(for section: DashboardSection) -> Binding<Bool> {
        Binding(
            get: { preferences.isDashboardSectionVisible(section) },
            set: { preferences.setDashboardSection(section, visible: $0) }
        )
    }
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 16)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPaneTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AboutHero()

            SettingsCard(title: "Support & Contact", systemImage: "bubble.left.and.bubble.right") {
                Text("Questions, bug reports, or feature requests? Reach the developer here:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SupportLinkButton(
                        title: "Discord",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        url: URL(string: "https://discord.gg/Cc2RGrN7dh")!
                    )
                }
            }
        }
    }
}

private struct AboutHero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: appIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("MenuWatt")
                    .font(.system(size: 22, weight: .bold))
                Text("Version \(versionString) (\(buildString))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("A lightweight macOS menu bar app for live power, battery, and system metrics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var appIconImage: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName), icon.size.width > 0 {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

private struct NotificationsSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPaneTitle(
                title: "Notifications",
                subtitle: "Get a macOS notification when battery, charging, or temperature events happen."
            )

            SettingsCard(title: "Battery", systemImage: "battery.50") {
                SettingsRow(label: "Notify when fully charged") {
                    Toggle("", isOn: $preferences.notifyChargeComplete)
                        .labelsHidden()
                }

                Divider()

                SettingsRow(label: "Notify when battery is low") {
                    Toggle("", isOn: $preferences.notifyLowBattery)
                        .labelsHidden()
                }

                if preferences.notifyLowBattery {
                    SettingsRow(label: "Low battery threshold") {
                        Stepper(
                            "\(preferences.lowBatteryThreshold)%",
                            value: $preferences.lowBatteryThreshold,
                            in: 5...50,
                            step: 5
                        )
                    }
                }
            }

            Text("Notifications are coalesced — the same alert won't fire more than once every 5 minutes. Grant permission in System Settings → Notifications → MenuWatt.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UpdatesSettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPaneTitle(
                title: "Updates",
                subtitle: "Check for new versions of MenuWatt on GitHub."
            )

            SettingsCard(title: "Update Check", systemImage: "arrow.triangle.2.circlepath") {
                SettingsRow(label: "Current version") {
                    Text(updateChecker.currentVersion)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                SettingsRow(label: "Check automatically") {
                    Toggle("", isOn: $preferences.autoCheckForUpdates)
                        .labelsHidden()
                }

                SettingsRow(label: "Last checked") {
                    Text(lastCheckedText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        Task {
                            _ = await updateChecker.check()
                            preferences.lastUpdateCheck = Date()
                        }
                    } label: {
                        if case .checking = updateChecker.status {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check Now")
                        }
                    }
                    .disabled(isChecking)
                }
                .padding(.top, 4)
            }

            statusCard
        }
    }

    private var isChecking: Bool {
        if case .checking = updateChecker.status { return true }
        return false
    }

    private var lastCheckedText: String {
        guard let date = preferences.lastUpdateCheck else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var statusCard: some View {
        switch updateChecker.status {
        case .updateAvailable(let release):
            SettingsCard(title: "Update Available", systemImage: "sparkles") {
                Text("Version \(release.tagName) is available.")
                    .font(.system(size: 13, weight: .semibold))
                if let body = release.body, !body.isEmpty {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Open Release") {
                        NSWorkspace.shared.open(release.htmlURL)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        case .upToDate:
            SettingsCard(title: "Up to Date", systemImage: "checkmark.seal") {
                Text("You're running the latest version of MenuWatt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            SettingsCard(title: "Check Failed", systemImage: "exclamationmark.triangle") {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .idle, .checking:
            EmptyView()
        }
    }
}

private struct SupportLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
