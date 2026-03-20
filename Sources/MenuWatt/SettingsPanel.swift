import AppKit
import SwiftUI

private enum SettingsPanelStyle {
    static let windowSize = NSSize(width: 900, height: 720)
    static let windowTitle = "MenuWatt Settings"
}

/// A standalone settings window for the app.
/// Since menu bar accessory apps cannot use SwiftUI's Settings scene reliably,
/// we host the settings view in a regular NSWindow.
@MainActor
final class SettingsPanel {

    private var window: NSWindow?
    private let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
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
        let settingsView = SettingsContentView(preferences: preferences)
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
    @State private var selectedPane: SettingsPane = .overview

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeroHeader(selectedPane: $selectedPane)

            Divider()

            ManualOnlyScrollView {
                selectedPaneView
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
        }
        .frame(
            minWidth: SettingsPanelStyle.windowSize.width,
            idealWidth: SettingsPanelStyle.windowSize.width,
            minHeight: SettingsPanelStyle.windowSize.height,
            idealHeight: SettingsPanelStyle.windowSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedPaneView: some View {
        switch selectedPane {
        case .overview:
            OverviewSettingsPane(preferences: preferences)
        case .about:
            AboutSettingsPane()
        }
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
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "house"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsHeroHeader: View {
    @Binding var selectedPane: SettingsPane

    var body: some View {
        VStack(spacing: 18) {
            Text("MenuWatt")
                .font(.system(size: 28, weight: .bold))

            HStack(spacing: 18) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsTabButton(
                        pane: pane,
                        isSelected: selectedPane == pane,
                        action: { selectedPane = pane }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct SettingsTabButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: pane.symbolName)
                    .font(.system(size: 28, weight: .semibold))
                Text(pane.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 104, height: 94)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
                subtitle: "Configure MenuWatt startup behavior."
            )

            SettingsCard(title: "Startup", systemImage: "power") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                if let launchAtLoginError = preferences.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            preferences.dismissLaunchAtLoginError()
                        }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 18) {
            SettingsPaneTitle(
                title: "About",
                subtitle: "MenuWatt is a lightweight battery and system monitor for your menu bar."
            )

            SettingsCard(title: "Features", systemImage: "sparkles") {
                Text("• Live battery and power status in the menu bar")
                Text("• CPU, memory, and storage monitoring")
                Text("• Animated pixel character driven by CPU load")
            }
        }
    }
}
