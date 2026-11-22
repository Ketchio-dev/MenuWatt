import AppKit
import SwiftUI

/// The sidebar and content shell of the Settings window.
///
/// Extracted from SettingsPanel.swift; rendering and identifiers unchanged.
struct SettingsContentView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var cleanup: MenuBarCleanupController
    @State private var selectedPane: SettingsPane

    init(preferences: AppPreferences, updateChecker: UpdateChecker,
         cleanup: MenuBarCleanupController, initialPane: SettingsPane) {
        self.preferences = preferences
        self.updateChecker = updateChecker
        self.cleanup = cleanup
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedPane)
                .frame(width: 176)
                .background(SettingsTheme.sidebar)

            Rectangle().fill(SettingsTheme.rule).frame(width: 1)

            ManualOnlyScrollView {
                selectedPaneView
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
            }
            .id(selectedPane)
            .accessibilityIdentifier("settings.\(selectedPane.rawValue)")
            .frame(maxWidth: .infinity)
            .background(SettingsTheme.canvas)
        }
        .modifier(SettingsControlsStyle())
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
        case .menuBar:
            MenuBarCleanupSettingsPane(cleanup: cleanup)
        case .updates:
            UpdatesSettingsPane(preferences: preferences, updateChecker: updateChecker)
        case .about:
            AboutSettingsPane()
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("MenuWatt").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(
                        pane: pane,
                        isSelected: selection == pane,
                        action: { selection = pane }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
    }

    private var appIconImage: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName), icon.size.width > 0 {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.symbolName)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? SettingsTheme.accent.opacity(0.12)
                          : Color.primary.opacity(isHovered ? 0.04 : 0))
            )
            .foregroundStyle(isSelected ? SettingsTheme.accent : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFocused ? SettingsTheme.accent : .clear, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("settings.navigation.\(pane.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
